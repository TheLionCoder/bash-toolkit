#!/bin/bash
#===================================================================
#    FILE: bq_cleanup.sh
#
#    USAGE: ./bq_cleanup.sh <PROJECT> <DATASET> <TABLES> [<DRY_RUN>] [<SURE>]
#
#    DESCRIPTION: Safely deletes a list of BigQuery tables. It checks if
#    each table exists before attempting deletion. Features a dry run
#    safety mode and an explicit confirmation requirement.
#
#    ARGUMENTS:
#      <PROJECT>   BigQuery project ID (e.g. my-project)
#      <DATASET>   BigQuery dataset ID (e.g. my_dataset)
#      <TABLES>    Space-separated list of tables (e.g. "table1 table2")
#      <DRY_RUN>   Set to "true" (default) to simulate actions, "false" to execute.
#      <SURE>      Must be "true" to confirm deletion when DRY_RUN is false.
#
#    REQUIREMENTS: bq (Google Cloud SDK BigQuery CLI tool)
#    AUTHOR: TheLionCoder
#    CREATED: 2026-06-03
#    REVISION: 1.0
#===================================================================

set -e

# Parse arguments
PROJECT=$1
DATASET=$2
TABLES=$3
DRY_RUN=${4:-true}  # Defaults to true for safety
SURE=${5:-false}    # Safety latch: must be true to actually perform modifications

# Check required parameters
if [[ -z "$PROJECT" || -z "$DATASET" || -z "$TABLES" ]]; then
  echo "Usage: $0 <PROJECT> <DATASET> <TABLES> [<DRY_RUN>] [<SURE>]"
  echo "Example: $0 my-project my_dataset \"table1 table2\" false true"
  exit 1
fi

if [ "$DRY_RUN" = "true" ]; then
  echo "--DRY_RUN Mode (No changes will made)--"
fi

if [ "$SURE" != "true" ] && [ "$DRY_RUN" = "false" ]; then
  echo "ERROR: Actual deletion requires SURE=true flag."
  exit 1
fi

for table in $TABLES; do
  FULL_PATH="$PROJECT:$DATASET.$table"

  if bq show "$FULL_PATH" >/dev/null 2>&1; then
    if [ "$DRY_RUN" = "true" ]; then
      echo "[ DRY_RUN ] would delete $FULL_PATH"
    else
      echo "Deleting $FULL_PATH..."
      bq rm -f "$FULL_PATH"
    fi
  else
    echo "SKIPPING: $FULL_PATH does not exist."
  fi
done
echo "Process completed Successfully"
