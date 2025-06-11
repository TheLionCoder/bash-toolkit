#!/bin/bash

# A script to parse log errors, extract metadata, and format it as CSV.
# This version is compatible with both GNU/Linux (WSL) and macOS environments.

# Validate BASE_DIR_ENV is set
if [[ -z "$BASE_DIR_ENV" ]]; then
  echo "ERROR: Environment variable BASE_DIR_ENV is not set." >&2
  exit 1
fi

# Ensure BASE_DIR_ENV ends with a trailing slash for consistent path joining
BASE_DIR_ENV="${BASE_DIR_ENV%/}/"

# Function to escape CSV fields according to RFC 4180.
# This ensures fields containing quotes or commas are handled correctly.
csv_escape() {
  local str="$1"
  # Double up existing double quotes
  str="${str//\"/\"\"}"
  # Enclose the entire string in double quotes
  printf '"%s"' "$str"
}

# Process each log line from standard input
while IFS= read -r line; do
  # Initialize variables for each line to prevent data bleed-over from previous lines
  rel_file=""
  file_name=""
  file_stem=""
  bill=""
  nit=""
  line_num=""
  error_type=""
  key=""
  expected=""
  actual_type=""
  period=""
  tech_provider=""
  model=""
  json_line=""
  processing_error=""
  include_json=false

  # Extract relative file path from the log line using sed for portability (macOS/WSL)
  # Original was: grep -oP "data/raw/[^']+"
  rel_file=$(sed -n "s/.*'\(data\/raw\/[^']\+\)'.*/\1/p" <<<"$line")

  if [[ -z "$rel_file" ]]; then
    processing_error="FILE_PATH_EXTRACTION_FAILED"
  else
    file_name="${rel_file##*/}"
    file_stem="${file_name%.*}"
    bill="${file_stem##*_}"
    nit="${file_stem%_*}"

    # Extract line number using sed for portability
    # Original was: grep -oP 'line \K\d+'
    line_num=$(sed -n 's/.* at line \([0-9]\+\).*/\1/p' <<<"$line")

    if [[ -z "$line_num" ]]; then
      # Handle cases where the error is not associated with a specific line
      line_num=1 # Assume line 1 for encoding or whole-file issues
    fi
  fi

  # Extract path components if the relative file was found
  if [[ -n "$rel_file" ]]; then
    IFS="/" read -ra path_parts <<<"$rel_file"
    tech_provider="${path_parts[2]:-}"
    period="${path_parts[4]:-}"
    model="${path_parts[5]:-}"
  fi

  # Categorize the error based on the log message content
  if [[ -z "$processing_error" ]]; then
    if [[ "$line" == *"invalid type:"* ]]; then
      error_type="invalid datatype"
      # Extract details using portable tools
      actual_type=$(echo "$line" | sed -n 's/.*invalid type: //p' | sed -e 's/[, ].*//' -e 's/[`"]//g')
      expected=$(echo "$line" | sed -n 's/.*expected \([^,]*\).*/\1/p' | sed 's/ at .*//' | xargs)
      # Flag that we need to fetch the JSON line content, unless it's the first line
      [[ "$line_num" -ne 1 ]] && include_json=true

    elif [[ "$line" == *"missing"* ]]; then
      error_type="missing field"
      key=$(echo "$line" | sed -n 's/.*missing \([^,]*\).*/\1/p' | sed 's/ at .*//' | xargs)
      expected="$key"

    elif [[ "$line" == *"input is out"* || "$line" == *"invalid date"* ]]; then
      error_type="wrong date"
      actual_type="invalid date format"
      expected="valid date format (e.g., YYYY-MM-DD)"
      # Flag that we need to fetch the JSON line content, unless it's the first line
      [[ "$line_num" -ne 1 ]] && include_json=true

    elif [[ "$line_num" -eq 1 && ("$line" == *"invalid character"* || "$line" == *"encoding"*) ]]; then
      error_type="encoding issues"
      actual_type="unknown"
      expected="UTF-8"
      # Entire file is the issue, so we don't fetch a specific JSON line
      json_line="File contains encoding errors; cannot parse."

    elif [[ "$line" == *"duplicate"* ]]; then
      error_type="bad structure"
      actual_type="duplicate key"
      expected="unique keys"

    else
      error_type="unknown_error"
      key=""
      expected=""
    fi
  else
    error_type="$processing_error"
  fi

  # If flagged, read the specific line from the JSON file
  if [[ "$include_json" == true && -n "$rel_file" && -n "$line_num" && "$line_num" -ne 1 ]]; then
    full_file_path="${BASE_DIR_ENV}${rel_file}"

    if [[ -f "$full_file_path" ]]; then
      # Get the specific line and trim leading/trailing whitespace
      json_line=$(sed -n "${line_num}p" "$full_file_path" | xargs)

      # Attempt to extract the key from the JSON line for better error reporting
      # This is a best-effort extraction for simple "key":"value" lines
      if [[ -z "$key" && "$json_line" == *:* ]]; then
        key=$(awk -F'"' '{print $2}' <<<"$json_line")
      fi
    else
      json_line="ERROR: Source file not found at ${full_file_path}"
    fi
  fi

  # Build the array of fields for the CSV output
  fields=(
    "$tech_provider" # tercero
    "$period"        # periodo
    "$model"         # modelo
    "$bill"          # factura
    "$nit"           # nit
    "$line_num"      # linea
    "$json_line"     # json
    "$error_type"    # error
    "$key"           # key
    "$expected"      # esperado
    "$actual_type"   # actual
  )

  # Escape each field and join them with a comma for the final CSV line
  escaped_fields=()
  for field in "${fields[@]}"; do
    escaped_fields+=("$(csv_escape "$field")")
  done
  (
    IFS=,
    printf "%s\n" "${escaped_fields[*]}"
  )
  unset IFS

done
