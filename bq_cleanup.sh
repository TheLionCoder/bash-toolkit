#!/bin/bash

set -e

PROJECT=$1
DATASET=$2
TABLES=$3
DRY_RUN=${4:-true}
SURE=${5:-false}

if [[ -z "$PROJECT" || -z "$DATASET" || -z "$TABLES" ]]; then
  echo "Usage: $0 <PROJECT> <DATASET> <TABLES> <DRY_RUN> <SURE>"
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
