#!/bin/bash
# Validate BASE_DIR_ENV is set
if [[ -z "$BASE_DIR_ENV" ]]; then
    echo "ERROR: Environment variable BASE_DIR_ENV is not set." >&2
    exit 1
fi

# Ensure BASE_DIR_ENV ends with a trailing slash
BASE_DIR_ENV="${BASE_DIR_ENV%/}/"

# Function to escape CSV fields
csv_escape() {
    local str="$1"
    str="${str//\"/\"\"}"  # Double existing double quotes
    printf '"%s"' "$str"    # Wrap in quotes
}

while IFS= read -r line; do
    # Initialize variables
    rel_file=""; file_name=""; file_stem=""; bill=""; nit=""
    line_num=""; error_type=""; key=""; expected=""; actual_type=""
    period=""; tech_provider=""; model=""; json_line=""
    processing_error=""; include_json=false

    # Extract filename and line number
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

    # Extract path components
    if [[ -n "$rel_file" ]]; then
        IFS="/" read -ra path_parts <<<"$rel_file"
        period="${path_parts[4]:-}"
        tech_provider="${path_parts[2]:-}"
        model="${path_parts[5]:-}"
    fi

    # Extract error details
    if [[ -z "$processing_error" ]]; then
        if [[ "$line" == *"invalid type:"* ]]; then
            error_type="invalid datatype"
            actual_type=$(grep -oP 'invalid type: \K(`[^`]*`|"[^"]*"|\S+)' <<<"$line" | sed -e 's/^[`"]//' -e 's/[`"]$//' -e 's/[[:space:]]*$//')
            expected=$(grep -oP 'expected \K[^,]+' <<<"$line" | sed 's/[[:space:]]*at line.*$//' | xargs)
            [[ "$line_num" -ne 1 ]] && include_json=true
        elif [[ "$line" == *"missing"* ]]; then
            error_type="missing field"
            key=$(grep -oP 'missing \K[^ ]+(?: [^ ]+)' <<<"$line")
            expected=$(grep -oP 'missing \K.*?(?= at |,|$)' <<<"$line")
        elif [[ "$line" == *"input is out"* ]]; then
            error_type="wrong date"
            actual_type="date string format"
            expected="date string correct format"
            [[ "$line_num" -ne 1 ]] && include_json=true
        elif [[ "$line_num" -eq 1 ]]; then
            error_type="encoding issues"
            actual_type="unknown"
            expected="UTF-8"
        else
            error_type="unknown_error"
            key=""
            expected=""
        fi
    else
        error_type="$processing_error"
    fi

    # Process JSON file for errors that need it (except line 1)
    if [[ "$include_json" == true && -n "$rel_file" && -n "$line_num" && "$line_num" -ne 1 ]]; then
        file="${BASE_DIR_ENV}${rel_file}"
        
        if [[ -f "$file" ]]; then
            if [[ "$line_num" =~ ^[0-9]+$ ]]; then
                # Get the specific line and clean it
                json_line=$(sed -n "${line_num}p" "$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                
                # Only include if it's a valid JSON line (contains :)
                if [[ "$json_line" == *:* ]]; then
                    # Extract key from JSON line
                    key=$(awk -F'"' '{print $2}' <<<"$json_line")
                else
                    json_line=""
                fi
            fi
        fi
    fi

    # Build CSV output
    fields=(
        "$tech_provider"   # tercero
        "$period"          # periodo
        "$model"           # modelo
        "$bill"            # factura
        "$nit"             # nit
        "$line_num"        # linea
        "$json_line"       # json
        "$error_type"      # error
        "$key"             # key
        "$expected"        # esperado
        "$actual_type"     # actual
    )
    
    # Escape and print CSV
    escaped_fields=()
    for field in "${fields[@]}"; do
        escaped_fields+=("$(csv_escape "$field")")
    done
    (IFS=,; printf "%s\n" "${escaped_fields[*]}")
    unset IFS

    # Reset variables for next iteration
    json_line=""
    actual_type=""
done
