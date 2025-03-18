#!/bin/bash

# Base directory (update this!)
BASE_DIR="/home/the_lion_coder/Developer/rips-processor/"

while IFS= read -r line; do
  # Extract filename and line number
  rel_file=$(grep -oP "data/raw/[^']+" <<<"$line")
  file_name=${rel_file##*/}
  line_num=$(grep -oP 'line \K\d+' <<<"$line")
  error=$(grep -oP 'invalid type: \K[^,]+' <<<"$line")
  mandatory=$(grep -oP 'expected \K[^ ]+(?: [^ ]+)*?(?= at line)' <<<"$line")

  # Build absolute path
  file="${BASE_DIR}${rel_file}"

  # Check if the file exists
  if [[ ! -f "$file" ]]; then
    echo "File: $rel_file | Line: $line_num | Error: FILE_NOT_FOUND"
    continue
  fi

  # Get the JSON line and preprocess (remove leading/trailing whitespace)
  json_line=$(sed -n "${line_num}p" "$file" | sed 's/^[ \t]*//; s/[ \t]*$//')

  # Extract key using awk
  key=$(awk -F'"' '{print $2}' <<<"$json_line")

  echo "File: $file_name | Line: $line_num | Key: $key | Error: $error | Mandatory: $mandatory"
done
