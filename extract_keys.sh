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
    line_num=""; error_type=""; key=""; expected=""
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
            error_type="invalid type"
            expected=$(grep -oP 'expected \K[^ ]+' <<<"$line")
            include_json=true  # Flag to include JSON for invalid errors
        elif [[ "$line" == *"invalid"* ]]; then
            error_type=$(grep -oP "invalid '\K[^,]+" <<<"$line")
            expected=$(grep -oP 'expected \K[^ ]+(?: [^ ]+)*?(?= at line)' <<<"$line")
            include_json=true  # Flag to include JSON for invalid errors
        elif [[ "$line" == *"missing"* ]]; then
            error_type="missing field"
            key=$(grep -oP 'missing \K[^ ]+(?: [^ ]+)' <<<"$line")
            expected=$(grep -oP 'missing \K.*?(?= at |,|$)' <<<"$line")
        else
            error_type="unknown_error"
            key=""
            expected=""
        fi
    else
        error_type="$processing_error"
    fi

    # Process JSON file only for invalid errors
    if [[ "$include_json" == true && -n "$rel_file" && -n "$line_num" ]]; then
        file="${BASE_DIR_ENV}${rel_file}"
        
        if [[ -f "$file" ]]; then
            # Validate line number
            if [[ "$line_num" =~ ^[0-9]+$ ]]; then
                total_lines=$(awk 'END {print NR}' "$file")
                if (( line_num <= total_lines && line_num >= 1 )); then
                    json_line=$(awk -v num="$line_num" 'NR == num {
                        gsub(/^[ \t]+|[ \t]+$/, "");
                        print;
                        exit
                    }' "$file")
                    
                    # Extract key from JSON line for invalid errors
                    if [[ "$error_type" == "invalid"* && -n "$json_line" ]]; then
                        key=$(awk -F'"' '{print $2}' <<<"$json_line")
                    fi
                fi
            fi
        fi
    fi

    # Build CSV output in required order:
    # tercero, periodo, modelo, factura, nit, linea, json, error, key, esperado
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
    )
    
    # Escape and print CSV
    escaped_fields=()
    for field in "${fields[@]}"; do
        escaped_fields+=("$(csv_escape "$field")")
    done
    # Use printf instead of echo and add error handling
    if ! (IFS=,; printf "%s\n" "${escaped_fields[*]}"); then
        echo "ERROR: Failed to write output at line $line_num" >&2
        exit 1
    fi
    unset IFS

    # Reset JSON line for next iteration
    json_line=""
done

