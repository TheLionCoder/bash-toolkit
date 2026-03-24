#!/bin/bash

BUCKET="$1"
SRC_FILE_PATTERN="$2"
DEST_DIR_PATTERN="$3"
DEST_FILE_NAME="$4"

if [ -z "$SRC_FILE_PATTERN" ] || [ -z "$DEST_DIR_PATTERN" ] || [ -z "$DEST_FILE_NAME" ] || [ -z "$BUCKET" ]; then
  echo "Usage: $0 <bucket> <src_file_pattern> <dest_dir_pattern> <dest_file_name>"
  echo "Example: $0 some-bkt folder/sub-folder/myfile-* folder/sub-folder/combinated/ combinated_file.csv"
  exit 1
fi

echo "Listing files matching: gs://$BUCKET/$SRC_FILE_PATTERN"
files=($(gcloud storage ls "gs://$BUCKET/$SRC_FILE_PATTERN" | sort))
total=${#files[@]}

echo "Found ${total} files."

if [ "$total" -eq 0 ]; then
  echo "No files found"
  exit 1
fi

if [ "$total" -le 32 ]; then
  echo "Composing $total files directly..."
  gcloud storage objects compose "${files[@]}" "gs://$BUCKET/$DEST_DIR_PATTERN/$DEST_FILE_NAME"
else
  echo "More than 32 files, composing in batches..."

  TEMP_DIR="gs://$BUCKET/$(dirname "$SRC_FILE_PATTERN")/temp_$(date +%s)"

  temp_files=()
  batch_num=1

  for ((i=0; i<total; i+=32)); do
    batch=("${files[@]:$i:32}")
    temp_file="$TEMP_DIR/batch_${batch_num}.csv"

    echo "Batch $batch_num: Composing ${#batch[@]} files..."
    gcloud storage objects compose "${batch[@]}" "$temp_file"

    temp_files+=("$temp_file")
    ((batch_num++))
  done

  echo "Composing ${#temp_files[@]} batch files into final destination"
  gcloud storage objects compose "${temp_files[@]}" "gs://$BUCKET/$DEST_DIR_PATTERN/$DEST_FILE_NAME"
  
  echo "Cleaning up temporary files.."
  gcloud storage rm -r "$TEMP_DIR"
fi
