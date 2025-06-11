#!/bin/bash
# Validate BASE_DIR_ENV is set
if [[ -z "$BASE_DIR_ENV" ]]; then
  echo "ERROR: Environment variable BASE_DIR_ENV is not set." >&2
  exit 1
fi

# Ensure BASE_DIR_ENV ends with a trailing slash
BASE_DIR_ENV="${BASE_DIR_ENV%/}/"

# Function to escape CSV fields
# This ensures that fields containing quotes or commas are handled correctly.
csv_escape() {
  local str="$1"
  str="${str//\"/\"\"}" # Double existing double quotes
  printf '"%s"' "$str"  # Wrap the entire string in quotes
}

# Process each line from stdin
while IFS= read -r line; do
  # Initialize variables for each line to prevent data bleed-over
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

  # Extract relative file path from the log line
  rel_file=$(grep -oP "data/raw/[^']+" <<<"$line" || true)
  if [[ -z "$rel_file" ]]; then
    processing_error="FILE_PATH_EXTRACTION_FAILED"
  else
    file_name="${rel_file##*/}"
    file_stem="${file_name%.*}"
    bill="${file_stem##*_}"
    nit="${file_stem%_*}"
    line_num=$(grep -oP 'line \K\d+' <<<"$line" || true)

    if [[ -z "$line_num" ]]; then
      processing_error="LINE_NUM_EXTRACTION_FAILED"
    fi
  fi

  # Extract path components if the relative file was found
  if [[ -n "$rel_file" ]]; then
    IFS="/" read -ra path_parts <<<"$rel_file"
    period="${path_parts[4]:-}"
    tech_provider="${path_parts[2]:-}"
    model="${path_parts[5]:-}"
  fi

  # Categorize the error based on the log message content
  if [[ -z "$processing_error" ]]; then
    if [[ "$line" == *"invalid type:"* ]]; then
      error_type="invalid datatype"
      actual_type=$(grep -oP 'invalid type: \K(`[^`]*`|"[^"]*"|\S+)' <<<"$line" | sed -e 's/^[`"]//' -e 's/[`"]$//' -e 's/[[:space:]]*$//')
      expected=$(grep -oP 'expected \K[^,]+' <<<"$line" | sed 's/[[:space:]]*at line.*$//' | xargs)
      # Flag that we need to fetch the JSON line content
      [[ "$line_num" -ne 1 ]] && include_json=true
    elif [[ "$line" == *"missing"* ]]; then
      error_type="missing field"
      key=$(grep -oP 'missing \K[^ ]+(?: [^ ]+)' <<<"$line")
      expected=$(grep -oP 'missing \K.*?(?= at |,|$)' <<<"$line")
    elif [[ "$line" == *"input is out"* ]]; then
      error_type="wrong date"
      actual_type="date string format"
      expected="date string correct format"
      # Flag that we need to fetch the JSON line content
      [[ "$line_num" -ne 1 ]] && include_json=true
    elif [[ "$line_num" -eq 1 ]]; then
      error_type="encoding issues"
      actual_type="unknown"
      expected="UTF-8"
    elif [[ "$line" == *"duplicate"* ]]; then
      error_type="bad structure"
      actual_type=""
      expected=""
    else
      error_type="unknown_error"
      key=""
      expected=""
    fi
  else
    error_type="$processing_error"
  fi

  # Process JSON file for errors that need it (datatype, date, etc.)
  if [[ "$include_json" == true && -n "$rel_file" && -n "$line_num" && "$line_num" -ne 1 ]]; then
    full_file_path="${BASE_DIR_ENV}${rel_file}"

    if [[ -f "$full_file_path" ]]; then
      # Get the specific line and clean leading/trailing whitespace
      json_line=$(sed -n "${line_num}p" "$full_file_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      # *** FIX: ***
      # The original script would clear json_line if it didn't contain a ':'.
      # Now, we preserve the line content and only *try* to extract a key if possible.
      if [[ "$json_line" == *:* ]]; then
        # Attempt to extract the key from the JSON line
        key=$(awk -F'"' '{print $2}' <<<"$json_line")
      fi
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
