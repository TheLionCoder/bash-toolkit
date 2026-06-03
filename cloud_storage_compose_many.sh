#!/bin/bash
#===================================================================
#    FILE: cloud_storage_compose_many.sh
#
#    USAGE: ./cloud_storage_compose_many.sh <bucket> <src_file_pattern> <dest_dir_pattern> <dest_file_name>
#
#    DESCRIPTION: Merges (composes) multiple files in Google Cloud Storage
#    into a single destination file. Because Google Cloud Storage limits
#    the `objects compose` operation to a maximum of 32 source objects,
#    this script implements a hierarchical (tree-like) composition
#    algorithm to recursively merge files in batches of 32. It cleans
#    up any intermediate temporary objects and deletes the original
#    source files upon successful completion.
#
#    ARGUMENTS:
#      <bucket>             The name of the GCS bucket (with or without 'gs://')
#      <src_file_pattern>   Glob/wildcard pattern of source files (e.g. folder/file-*)
#      <dest_dir_pattern>   Destination directory path (e.g. folder/combined/)
#      <dest_file_name>     Filename of the merged output (e.g. combined.csv)
#
#    REQUIREMENTS: gcloud CLI (Google Cloud SDK) with storage permissions
#    AUTHOR: TheLionCoder
#    CREATED: 2026-06-03
#    REVISION: 1.0
#===================================================================

set -euo pipefail

# Parse inputs
BUCKET="$1"
SRC_FILE_PATTERN="$2"
DEST_DIR_PATTERN="$3"
DEST_FILE_NAME="$4"

# Validate required arguments
if [ -z "$SRC_FILE_PATTERN" ] || [ -z "$DEST_DIR_PATTERN" ] || [ -z "$DEST_FILE_NAME" ] || [ -z "$BUCKET" ]; then
  echo "Usage: $0 <bucket> <src_file_pattern> <dest_dir_pattern> <dest_file_name>"
  echo "Example: $0 some-bkt \"folder/sub-folder/myfile-*\" \"folder/sub-folder/combined/\" combined_file.csv"
  exit 1
fi

# Normalize bucket name: remove leading gs:// and trailing slash
BUCKET="${BUCKET#gs://}"
BUCKET="${BUCKET%/}"

# Normalize destination directory pattern: remove trailing and leading slashes
DEST_DIR_PATTERN="${DEST_DIR_PATTERN%/}"
DEST_DIR_PATTERN="${DEST_DIR_PATTERN#/}"

FINAL_DEST="gs://$BUCKET/$DEST_DIR_PATTERN/$DEST_FILE_NAME"

echo "Listing files matching: gs://$BUCKET/$SRC_FILE_PATTERN"
FILES_TMP=$(mktemp)

# Query GCS and sort matching source files, saving them to a temporary local file
gcloud storage ls "gs://$BUCKET/$SRC_FILE_PATTERN" | sort >"$FILES_TMP"

files=()
while IFS= read -r line || [[ -n "$line" ]]; do
  files+=("$line")
done <"$FILES_TMP"
total=${#files[@]}
rm "$FILES_TMP"

echo "Found ${total} files."

# Validate file counts
if [ "$total" -eq 0 ]; then
  echo "Error: No files found matching gs://$BUCKET/$SRC_FILE_PATTERN"
  exit 1
fi

# Optimization: if only 1 file is found, bypass composition and just copy it to destination
if [ "$total" -eq 1 ]; then
  echo "Only one file found. Copying to destination..."
  gcloud storage cp "${files[0]}" "$FINAL_DEST"
  exit 0
fi

# Define temporary path in the GCS bucket for intermediate hierarchical compose objects
TIMESTAMP=$(date +%s)
TEMP_BASE="gs://$BUCKET/tmp/compose_$TIMESTAMP"

current_files=("${files[@]}")

# GCS objects compose has a hard limit of 32 source objects per compose operation.
# We iteratively reduce the file list by composing batches of up to 32 objects,
# until the list size is <= 32.
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

# Perform the final composition of the remaining files (all <= 32)
echo "Final composition: Composing ${#current_files[@]} files into $FINAL_DEST"
gcloud storage objects compose "${current_files[@]}" "$FINAL_DEST"

echo "Cleaning up temporary files..."
# Delete the folder containing intermediate composite chunks
gcloud storage rm -r "$TEMP_BASE" || echo "Warning: Could not clean up temporary folder $TEMP_BASE"

echo "Deleting original source files..."
# Delete original files in batches of 100 to avoid CLI argument length limit
for ((i = 0; i < ${#files[@]}; i += 100)); do
  batch=("${files[@]:$i:100}")
  safe_batch=()
  for f in "${batch[@]}"; do
    # Safety check to avoid deleting the newly created final destination file
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
