#!/bin/bash
#
# bq_table_copy.sh
#
# A production ready script to copy multiple tables in parallel
# from a source dataset to a destination dataset.
#
# Author: Orlando Reyes <evoreyes@epsssanitas.com>
#
# v 0.15 - Fixed syntax error and improved command execution robustness
#
# v 0.14

# -----
#  Script configuration
# -----

# Exit on error
set -euo pipefail

# -----
# Global constants
# -----
SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_NAME
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[0;33m'
readonly NC='\033[0m' # No color
DEFAULT_MAX_PARALLEL=4

# -----
# Logging functions
# -----
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_debug() { echo -e "[DEBUG] $*"; }

# ----
# Utility Functions
# ----
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME -s <SRC_PROJECT:DATASET> -d <DEST_PROJECT:DATASET> -t <TABLES> [OPTIONS]

Copies a list of bigquery tables from a source to destination dataset in parallel.

Required:
  -s <PROJECT:DATASET> Source project and dataset (e.g., "co-repository-some:some_dataset")
  -d <PROJECT:DATASET> Destination project and dataset
  -t <TABLE_LIST>      Comma separated string of tables names to copy
                       (e.g., "table1,table2,table3") 

Options:
  -j <NUM>             Number of parallel copy jobs to run. 
                       (Default: $DEFAULT_MAX_PARALLEL)
  -f                   Force overwrite destination tables if they exist
  -l <LOG_DIR>         Specify the directory to store the logs
                       (Default: Creates a tmp directory)
  -v                   Verbose mode - show bq commands being executed
  -h                   Display the help message 

Example:
  $SCRIPT_NAME -s "co-ingest:raw_dataset" -d "co-prod:dataset" -t "usuarios,consultas" -j 8 -f
EOF
}

# Check for dependencies
check_dependencies() {
  local missing=0
  for cmd in "bq" "parallel"; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Required command '$cmd' is not found in PATH."
      missing=1
    fi
  done

  if [ "$missing" -eq 1 ]; then
    log_error "Please install missing dependencies and try again."
    exit 1
  fi
  log_info "All dependencies (bq, parallel) are satisfied."
}

# Clean function to remove temporary log directory
cleanup() {
  if [ -n "${LOG_DIR_TMP:-}" ] && [ -d "${LOG_DIR_TMP}" ]; then
    log_info "Cleaning up temporary log directory: $LOG_DIR_TMP"
    rm -rf "$LOG_DIR_TMP"
  fi
}

# -----
# Core task function
# -----

copy_table_parallel() {
  local table_name=$1
  local src_project=$2
  local src_dataset=$3
  local dest_project=$4
  local dest_dataset=$5
  local log_dir=$6
  local force_overwrite=$7
  local verbose=$8

  local src_table="${src_project}:${src_dataset}.${table_name}"
  local dest_table="${dest_project}:${dest_dataset}.${table_name}"
  local log_file="${log_dir}/bq_copy_${table_name}.log"
  local status_file="${log_dir}/status_${table_name}.txt"

  echo "STARTED" >"$status_file"

  log_info "Copying: '${table_name}'"

  echo "=== Verifying source table ===" >>"$log_file"
  if ! bq show "$src_table" >>"$log_file" 2>&1; then
    log_error "Source table does not exist: '$src_table'"
    echo "FAILED" >"$status_file"
    return 1
  fi
  echo "Source table verified" >>"$log_file"

  echo "=== Verifying destination table ===" >>"$log_file"
  if bq show "$dest_table" >/dev/null 2>&1; then
    echo "Destination table '$dest_table' already exists." >>"$log_file"
    if [ "$force_overwrite" = "true" ]; then
      echo "Force mode (-f) is ON. Proceeding to delete and recreate." >>"$log_file"
      echo "=== Deleting destination table ===" >>"$log_file"
      if ! bq rm -f "$dest_table" >>"$log_file" 2>&1; then
        log_error "✗ Failed to delete existing destination table: '$dest_table'"
        echo "FAILED" >"$status_file"
        return 1
      fi
      echo "Existing destination table deleted." >>"$log_file"
    else
      log_error "✗ Destination table '$dest_table' already exists. Use -f to recreate."
      echo "FAILED" >"$status_file"
      return 1
    fi
  else
    echo "Destination table does not exist. Proceeding with copy." >>"$log_file"
  fi

  local bq_cmd_args=("bq" "cp" "$src_table" "$dest_table")

  if [ "$verbose" = "true" ]; then
    log_debug "Executing: ${bq_cmd_args[*]}"
  fi
  {
    echo "=== Executing command ==="
    echo "${bq_cmd_args[*]}"
  } >>"$log_file"

  echo "=== Copy output ===" >>"$log_file"
  if "${bq_cmd_args[@]}" >>"$log_file" 2>&1; then
    echo "=== Verifying copy ===" >>"$log_file"
    sleep 1
    if bq show "$dest_table" >>"$log_file" 2>&1; then
      log_success "✓ Completed: '$table_name'"
      echo "SUCCESS" >"$status_file"
      return 0
    else
      log_error "✗ Copy command succeeded but destination table not found post-copy: '$table_name'"
      echo "FAILED" >"$status_file"
      return 1
    fi
  else
    log_error "✗ bq cp command failed: '$table_name'"
    echo "FAILED" >"$status_file"
    return 1
  fi
}

# Export the function and variables for GNU parallel to use.
export -f copy_table_parallel log_info log_error log_success log_debug
export GREEN RED YELLOW NC

# ----
# Main Execution
# ----

main() {
  # Set trap to clean up tmp directory on exit
  trap cleanup EXIT INT TERM

  # --- Argument parsing ---
  local src_full=""
  local dest_full=""
  local tables_csv=""
  local max_parallel=$DEFAULT_MAX_PARALLEL
  local log_dir_base=""
  local force_overwrite="false"
  local verbose="false"

  while getopts ":s:d:t:j:l:fvh" opt; do
    case $opt in
    s) src_full="$OPTARG" ;;
    d) dest_full="$OPTARG" ;;
    t) tables_csv="$OPTARG" ;;
    j) max_parallel="$OPTARG" ;;
    l) log_dir_base="$OPTARG" ;;
    f) force_overwrite="true" ;;
    v) verbose="true" ;;
    h)
      usage
      exit 0
      ;;
    \?)
      log_error "Invalid option: -$OPTARG"
      usage
      exit 1
      ;;
    :)
      log_error "Option -$OPTARG requires an argument."
      usage
      exit 1
      ;;
    esac
  done

  # --- Input Validation ---
  if [ -z "$src_full" ] || [ -z "$dest_full" ] || [ -z "$tables_csv" ]; then
    log_error "Missing required arguments: -s, -d, and -t are all required."
    usage
    exit 1
  fi

  if ! [[ "$src_full" =~ ^[^:]+:[^:]+$ ]] || ! [[ "$dest_full" =~ ^[^:]+:[^:]+$ ]]; then
    log_error "Invalid format for source or destination. Must be 'project:dataset'."
    usage
    exit 1
  fi

  if ! [[ "$max_parallel" =~ ^[0-9]+$ ]] || [[ "$max_parallel" -lt 1 ]]; then
    log_error "Parallel jobs (-j) must be a positive integer."
    usage
    exit 1
  fi

  check_dependencies

  # --- setup ---
  local src_project
  src_project=$(echo "$src_full" | cut -d: -f1)
  local src_dataset
  src_dataset=$(echo "$src_full" | cut -d: -f2)
  local dest_project
  dest_project=$(echo "$dest_full" | cut -d: -f1)
  local dest_dataset
  dest_dataset=$(echo "$dest_full" | cut -d: -f2)

  # Verify source dataset exists
  log_info "Verifying source dataset exists..."
  if ! bq show "${src_project}:${src_dataset}" &>/dev/null; then
    log_error "Source dataset does not exist: '${src_project}:${src_dataset}'"
    exit 1
  fi
  log_info "Source dataset verified ✓"

  # Verify destination dataset exists
  log_info "Verifying destination dataset exists..."
  if ! bq show "${dest_project}:${dest_dataset}" &>/dev/null; then
    log_error "Destination dataset does not exist: '${dest_project}:${dest_dataset}'"
    log_info "You may need to create it first with: bq mk ${dest_project}:${dest_dataset}"
    exit 1
  fi
  log_info "Destination dataset verified ✓"

  # LOG_DIR_TMP is intentionally global so the trap/cleanup function can find it
  if [ -n "$log_dir_base" ]; then
    LOG_DIR_TMP="$log_dir_base/bq_copy_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$LOG_DIR_TMP"
  else
    LOG_DIR_TMP=$(mktemp -d "/tmp/${SCRIPT_NAME}.logs.XXXXXX")
  fi

  log_info "Starting BigQuery parallel copy run..."
  log_info "Source:      '$src_project:$src_dataset'"
  log_info "Destination: '$dest_project:$dest_dataset'"
  log_info "Jobs:         $max_parallel"
  log_info "Force:        $force_overwrite"
  log_info "Verbose:      $verbose"
  log_info "Logs:        '$LOG_DIR_TMP'"

  local tables_to_copy=()
  while IFS=',' read -ra ADDR; do
    for table in "${ADDR[@]}"; do
      table=$(echo "$table" | xargs)
      if [ -n "$table" ]; then
        tables_to_copy+=("$table")
      fi
    done
  done <<<"$tables_csv"

  log_info "Total tables to copy: ${#tables_to_copy[@]}"

  # --- Parallel Execution ---

  log_info "Starting parallel copy process..."

  # Run parallel without halt flag to let all jobs attempt to complete
  # Pipe the array of tables, one per line, into parallel
  printf '%s\n' "${tables_to_copy[@]}" |
    command parallel \
      --jobs "$max_parallel" \
      --bar \
      --joblog "${LOG_DIR_TMP}/parallel_job_log.txt" \
      copy_table_parallel {} "$src_project" "$src_dataset" "$dest_project" "$dest_dataset" "$LOG_DIR_TMP" "$force_overwrite" "$verbose"

  echo ""
  log_info "Checking results..."

  # Check status files to determine success/failure
  local success_count=0
  local failed_count=0
  local failed_tables=()

  for table in "${tables_to_copy[@]}"; do
    local status_file="${LOG_DIR_TMP}/status_${table}.txt"
    if [ -f "$status_file" ]; then
      local status
      status=$(cat "$status_file")
      if [ "$status" = "SUCCESS" ]; then
        ((success_count++))
      else
        ((failed_count++))
        failed_tables+=("$table")
      fi
    else
      ((failed_count++))
      failed_tables+=("$table (no status)")
    fi
  done

  log_info "Results: $success_count succeeded, $failed_count failed"

  if [ $failed_count -eq 0 ]; then
    log_success "All ${#tables_to_copy[@]} tables copied successfully!"
    log_info "Verify with: bq ls ${dest_project}:${dest_dataset}"
    exit 0
  else
    log_error "Failed tables:"
    for table in "${failed_tables[@]}"; do
      log_error "  - $table"
      local log_file="${LOG_DIR_TMP}/bq_copy_${table}.log"
      if [ -f "$log_file" ]; then
        log_error "    Log: $log_file"
      fi
    done
    log_error "Check logs in $LOG_DIR_TMP for details."
    exit 1
  fi
}

# Execute the main function, passing all script arguments
main "$@"
