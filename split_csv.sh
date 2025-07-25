#!/bin/bash

#===================================================================
#    FILE: split_csv.sh
#
#    USAGE: ./split_csv.sh <output_directory> <max_size_in_mb> /path/to/file1.csv [/path/to/file2.csv ...]
#
#    DESCRIPTION: Split a large csv into smaller chunks of specified
#    max size in MB. It ensures the header row from the origina
#    file is included in every chunk.
#
#    OPTIONS: --
#    REQUIREMENTS: awk
#    BUGS: --
#    NOTES --
#    AUTHOR: TheLionCoder
#    CREATED: 2025-07-25 11:07:00
#    REVISION: 0.3
#===================================================================

set -e
set -o pipefail

split_single_file() {
  local INPUT_FILE="$1"
  local OUTPUT_DIR="$2"
  local MAX_SIZE_MB="$3"

  if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file: '$INPUT_FILE' not found. Skipping"
    return 1
  fi

  local BASENAME
  BASENAME=$(basename -- "$INPUT_FILE")
  local FILENAME
  FILENAME="${BASENAME%.*}"

  local MAX_SIZE_BYTES
  MAX_SIZE_BYTES=$((MAX_SIZE_MB * 1024 * 1024))

  echo "-> processing '$INPUT_FILE'..."
  echo "  Splitting into chunks of max ${MAX_SIZE_MB}MB..."

  # Use awk to process the file line-by-line
  # This is memory efficient as it doesnot load the whole file at once.
  awk -v max_size="$MAX_SIZE_BYTES" \
    -v output_dir="$OUTPUT_DIR" \
    -v filename_base="$FILENAME" '
    BEGIN {
      file_count = 1;
      current_size = 0;
    }
    NR == 1 {
      header = $0;
      output_file = sprintf("%s/%s_part_%d.csv", output_dir, filename_base, file_count);
      print header > output_file;
      current_size = length(header) + 1;
      next;
    }
    {
      line_size = length($0) + 1;

      # Check if adding a new line would exceed the max size
      if (current_size + line_size > max_size && current_size > length(header) + 1) {
        # If it exceeds close the current file
        close(output_file)

        file_count++;
        output_file = sprintf("%s/%s_part_%d.csv", output_dir, filename_base, file_count);

        print header > output_file;

        # Reset the current size to the size of the header
        current_size = length(header) + 1;
      }

      # Print the current line to the output_file
      print $0 >> output_file;

      current_size += line_size;
    }
    END {
      if (output_file) {
        close(output_file);
      }
      printf("Splitting complete! %d chunks created in '%s'\n", file_count, output_dir);
    }
  ' "$INPUT_FILE"
}

# Main

if [ "$#" -lt 3 ]; then
  echo "USAGE: $0 <output_directory> <max_size_in_mb> <input_csv_file_or_dir1> [input_csv_file_or_dir2...]"
  exit 1
fi

OUTPUT_DIR="$1"
MAX_SIZE_MB="$2"

# Remove the first two arguments, leaving only the list of input files.
shift 2

if [ ! -d "$OUTPUT_DIR" ]; then
  echo "Error: Output directory: '$OUTPUT_DIR' not found. Creating it!..."
  mkdir -p "$OUTPUT_DIR"
fi

for INPUT_PATH in "$@"; do
  if [ ! -e "$INPUT_PATH" ]; then
    echo "Warning: Input path '$INPUT_PATH' not found. Skipping..."
    continue
  fi

  if [ -d "$INPUT_PATH" ]; then
    echo "Processing directory: '$INPUT_PATH'..."
    find "$INPUT_PATH" -maxdepth 1 -type f -name "*.csv" -print0 | while IFS= read -r -d '' file; do
      split_single_file "$file" "$OUTPUT_DIR" "$MAX_SIZE_MB"
      echo "--------------------------------------------------"
    done

  elif [ -f "$INPUT_PATH" ]; then
    split_single_file "$INPUT_PATH" "$OUTPUT_DIR" "$MAX_SIZE_MB"
    echo "--------------------------------------------------"
  fi
done

echo "All processing complete!"
