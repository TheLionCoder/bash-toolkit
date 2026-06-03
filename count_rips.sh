#!/bin/bash
#===================================================================
#    FILE: count_rips.sh
#
#    USAGE: ./count_rips.sh <key> <path>
#
#    DESCRIPTION: Searches for all JSON files in the specified path
#    representing RIPS files, and uses jq to find the maximum
#    consecutivo (serial number) for a specific service key (e.g. ap, ac, am).
#
#    ARGUMENTS:
#      <key>    The service identifier (e.g. "ac" for consultations, "ap" for procedures)
#      <path>   Directory path containing JSON files to inspect
#
#    REQUIREMENTS: jq (JSON CLI parser)
#    AUTHOR: TheLionCoder
#    CREATED: 2026-06-03
#    REVISION: 1.0
#===================================================================

# Ensure both service key and path are provided
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <key> <path>"
  echo "Example: $0 ac ./data/raw"
  exit 1
fi

KEY="$1"
DATA_PATH="$2"

# Traverse the directory, finding all JSON files
find "$DATA_PATH" -type f -name "*.json" |
  while read -r file; do
    # Run jq to navigate: .usuarios[] -> .servicios[<KEY>][] -> get .consecutivo
    # Extract the maximum value or output 0 if no records are found
    jq -r --arg file_name "$file" --arg key "$KEY" '
    [.usuarios[].servicios[$key]? // [] | .[].consecutivo] |
      if length > 0 then max as $max | "\($file_name) | \($max)"
      else "\($file_name) | 0" end' "$file"
  done
