#!/bin/bash

# Base directory (update this!)
BASE_DIR="/home/the_lion_coder/Developer/rips-processor/"

while IFS= read -r line; do
  # Extract filename and line number
  rel_filename=$(grep -oP "data/raw/[^']+" <<<"$line")
  line_num=$(grep -oP 'line \K\d+' <<<"$line")
  error=$(grep -oP 'invalid type: \K[^,]+' <<<"$line")
  mandatory=$(grep -oP 'expected \K[^ ]+(?: [^ ]+)*?(?= at line)' <<<"$line")

  # Build absolute path
  filename="${BASE_DIR}${rel_filename}"

  # Check if the file exists
  if [[ ! -f "$filename" ]]; then
    echo "File: $rel_filename | Line: $line_num | Error: FILE_NOT_FOUND"
    continue
  fi

  # Get the JSON line and preprocess (remove leading/trailing whitespace)
  json_line=$(sed -n "${line_num}p" "$filename" | sed 's/^[ \t]*//; s/[ \t]*$//')

  # Debug: Print the raw line
  # echo "DEBUG: Line $line_num: '$json_line'"

  # Extract key using awk
  key=$(awk -F'"' '{print $2}' <<<"$json_line")

  echo "File: $rel_filename | Line: $line_num | Key: '$key' | Error: '$error' | Mandatory: '$mandatory'"
done
