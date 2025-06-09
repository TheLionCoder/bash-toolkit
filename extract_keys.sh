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
    processing_error=""

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

    # Process JSON file if possible
    if [[ -z "$processing_error" ]]; then
        file="${BASE_DIR_ENV}${rel_file}"
        
        if [[ ! -f "$file" ]]; then
            processing_error="FILE_NOT_FOUND"
        else
            # Validate line number
            if [[ ! "$line_num" =~ ^[0-9]+$ ]]; then
                processing_error="INVALID_LINE_NUMBER"
            else
                total_lines=$(awk 'END {print NR}' "$file")
                if (( line_num > total_lines || line_num < 1 )); then
                    processing_error="INVALID_LINE_NUMBER"
                else
                    json_line=$(awk -v num="$line_num" 'NR == num {
                        gsub(/^[ \t]+|[ \t]+$/, "");
                        print;
                        exit
                    }' "$file")
                fi
            fi
        fi
    fi

    # Extract error details if no processing errors
    if [[ -z "$processing_error" ]]; then
        if [[ "$line" == *"invalid"* ]]; then
            error_type=$(grep -oP 'invalid \K[^,]+' <<<"$line" || true)
            key=$(grep -oP "key '\K[^']+" <<<"$line" || true)
            expected=$(grep -oP 'expected \K[^ ]+(?: [^ ]+)*?(?= at line)' <<<"$line" || true)
        elif [[ "$line" == *"missing"* ]]; then
            error_type="missing"
            key=$(grep -oP "missing key '\K[^']+" <<<"$line" || true)
            expected=""  # No expected value for missing keys
        else
            error_type="unknown_error"
            key=""
            expected=""
        fi
    else
        # Use processing error as the error type
        error_type="$processing_error"
        key=""
        expected=""
    fi

    # Build CSV output in required order:
    # tercero, periodo, modelo, JSON, factura, nit, linea, key, error, esperado
    fields=(
        "$tech_provider"   # tercero
        "$period"          # periodo
        "$model"           # modelo
        "$json_line"       # JSON
        "$bill"            # factura
        "$nit"             # nit
        "$line_num"        # linea
        "$key"             # key
        "$error_type"      # error
        "$expected"        # esperado
    )
    
    # Escape and print CSV
    escaped_fields=()
    for field in "${fields[@]}"; do
        escaped_fields+=("$(csv_escape "$field")")
    done
    IFS=,; echo "${escaped_fields[*]}"; unset IFS

done
