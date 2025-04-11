#!/bin/bash

# Base directory (update this!)
BASE_DIR="/home/the_lion_coder/Developer/rips-processor/"

while IFS= read -r line; do
  # Extract filename and line number
  rel_file=$(grep -oP "data/raw/[^']+" <<<"$line")
  file_name=${rel_file##*/}
  file_stem=${file_name%.*}
  bill=${file_stem##*_}
  nit=${file_stem%_*}
  line_num=$(grep -oP 'line \K\d+' <<<"$line")
  mandatory=$(grep -oP 'expected \K[^ ]+(?: [^ ]+)*?(?= at line)' <<<"$line")

  if [[ "$line" == *"invalid"* ]]; then
    error=$(grep -oP 'invalid \K[^,]+' <<<"$line")
  elif [[ "$line" == *"missing"* ]]; then
    error=$(grep -oP 'missing \K[^,]+' <<<"$line")
  else
    error="unknown_error"
  fi

  IFS="/" read -ra path_parts <<<"$rel_file"
  period=${path_parts[2]}
  tech_provider=${path_parts[3]}
  model=${path_parts[4]}

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
  echo "Provider: $tech_provider | Period: $period | Model: $model | File: $file_name | Bill: $bill | Nit: $nit | Line: $line_num | Key: $key | Error: $error | Mandatory: $mandatory"
done
