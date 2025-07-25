#!/bin/bash

#===================================================================
#    FILE: split_csv.sh
#
#    USAGE: ./split_csv.sh /path/to_large_csv /path/output_dir/ 10
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
#    REVISION: 0.1
#===================================================================

if [ "$#" -ne 3 ]; then
  echo "USAGE: $0 <input_csv_file> <output_directory> <max_size_in_mb>"
  exit 1
fi

INPUT_FILE="$1"
OUTPUT_DIR="$2"
MAX_SIZE_MB="$3"

if [ ! -f "$INPUT_FILE" ]; then
  echo "Error: Input file: '$INPUT_FILE' not found."
fi

if [ ! -d "$OUTPUT_DIR" ]; then
  echo "Error: Output directory: '$OUTPUT_DIR' not found. Creating it!..."
  mkdir -p "$OUTPUT_DIR"
fi

BASENAME=$(basename -- "$INPUT_FILE")
FILENAME="${BASENAME%.*}"

MAX_SIZE_BYTES=$((MAX_SIZE_MB * 1024 * 1024))

echo "Starting to split '$INPUT_FILE' into chunks of max ${MAX_SIZE_MB}MB..."

# Use awk to process the file line-by-line
# This is memory efficient as it doesnot load the whole file at once.
awk -v max_size="$MAX_SIZE_BYTES" \
  -v output_dir="$OUTPUT_DIR" \
  -v filename_base="$FILENAME" '
BEGIN {
  file_count = 1;
  current_size = 0;
  header_saved = 0;
}
{
  if (!header_saved) {
    header = $0;
    header_saved = 1;
    output_file = sprintf("%s/%s_part_%d.csv", output_dir, filename_base, file_count);
    print header > output_file;
    current_size = length(header) + 1;
    next;
  }
  
  line_size = length($0) + 1;

  # Check if adding a new line would exceed the max size
  if (current_size + line_size > max_size) {
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
