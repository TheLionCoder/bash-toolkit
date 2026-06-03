#!/bin/bash
#===================================================================
#    FILE: count_users_rips.sh
#
#    USAGE: ./count_users_rips.sh <path>
#
#    DESCRIPTION: Searches for all JSON files in the specified path,
#    and uses jq to find the maximum consecutivo (serial number) 
#    directly under the main usuarios array.
#
#    ARGUMENTS:
#      <path>   Directory path containing JSON files to inspect
#
#    REQUIREMENTS: jq (JSON CLI parser)
#    AUTHOR: TheLionCoder
#    CREATED: 2026-06-03
#    REVISION: 1.0
#===================================================================

# Check required parameters
if [ -z "$1" ]; then
  echo "Usage: $0 <path>"
  echo "Example: $0 ./data/raw"
  exit 1
fi

DATA_PATH="$1"

# Traverse the directory, finding all JSON files
find "$DATA_PATH" -type f -name "*.json" |
  while read -r file; do
    # Run jq to navigate: .usuarios[] -> get .consecutivo
    # Extract the maximum value or output 0 if no records are found
    jq -r --arg file_name "$file" '
    [.usuarios[]? // [] | .consecutivo?] |
      if length > 0 then max as $max | "\($file_name) | \($max)"
      else "\($file_name) | 0" end' "$file"
  done
