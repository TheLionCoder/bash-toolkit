#!/bin/bash

set -euo pipefail

BUCKET="$1"
SRC_FILE_PATTERN="$2"
DEST_DIR_PATTERN="$3"
DEST_FILE_NAME="$4"

if [ -z "$SRC_FILE_PATTERN" ] || [ -z "$DEST_DIR_PATTERN" ] || [ -z "$DEST_FILE_NAME" ] || [ -z "$BUCKET" ]; then
  echo "Usage: $0 <bucket> <src_file_pattern> <dest_dir_pattern> <dest_file_name>"
  echo "Example: $0 some-bkt folder/sub-folder/myfile-* folder/sub-folder/combined/ combined_file.csv"
  exit 1
fi

BUCKET="${BUCKET#gs://}"
BUCKET="${BUCKET%/}"

DEST_DIR_PATTERN="${DEST_DIR_PATTERN%/}"
DEST_DIR_PATTERN="${DEST_DIR_PATTERN#/}"

FINAL_DEST="gs://$BUCKET/$DEST_DIR_PATTERN/$DEST_FILE_NAME"

echo "Listing files matching: gs://$BUCKET/$SRC_FILE_PATTERN"
FILES_TMP=$(mktemp)
gcloud storage ls "gs://$BUCKET/$SRC_FILE_PATTERN" | sort >"$FILES_TMP"

files=()
while IFS= read -r line || [[ -n "$line" ]]; do
  files+=("$line")
done <"$FILES_TMP"
total=${#files[@]}
rm "$FILES_TMP"

echo "Found ${total} files."

if [ "$total" -eq 0 ]; then
  echo "Error: No files found matching gs://$BUCKET/$SRC_FILE_PATTERN"
  exit 1
fi

if [ "$total" -eq 1 ]; then
  echo "Only one file found. Copying to destination..."
  gcloud storage cp "${files[0]}" "$FINAL_DEST"
  exit 0
fi

TIMESTAMP=$(date +%s)
TEMP_BASE="gs://$BUCKET/tmp/compose_$TIMESTAMP"

current_files=("${files[@]}")

level=1
while [ ${#current_files[@]} -gt 32 ]; do
  echo "Level $level: Reducing ${#current_files[@]} files into batches..."
  next_level_files=()
  batch_num=1

  for ((i = 0; i < ${#current_files[@]}; i += 32)); do
    batch=("${current_files[@]:$i:32}")
    temp_file="$TEMP_BASE/level${level}_batch${batch_num}.tmp"

    echo "  Level $level Batch $batch_num: Composing ${#batch[@]} files..."
    gcloud storage objects compose "${batch[@]}" "$temp_file"

    next_level_files+=("$temp_file")
    ((batch_num++))
  done

  current_files=("${next_level_files[@]}")
  ((level++))
done

echo "Final composition: Composing ${#current_files[@]} files into $FINAL_DEST"
gcloud storage objects compose "${current_files[@]}" "$FINAL_DEST"

echo "Cleaning up..."

gcloud storage rm -r "$TEMP_BASE" || echo "Warning: Could not clean up temporary folder $TEMP_BASE"

echo "Deleting original source files..."
for ((i = 0; i < ${#files[@]}; i += 100)); do
  batch=("${files[@]:$i:100}")
  safe_batch=()
  for f in "${batch[@]}"; do
    if [ "$f" != "$FINAL_DEST" ]; then
      safe_batch+=("$f")
    else
      echo "Skipping deletion of destination file: $f"
    fi
  done

  if [ ${#safe_batch[@]} -gt 0 ]; then
    gcloud storage rm "${safe_batch[@]}"
  fi
done

echo "Done! Final file at: $FINAL_DEST"
