#!/bin/bash
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $1 <key> <path>"
  exit 1
fi

KEY="$1"
DATA_PATH="$2"

find "$DATA_PATH" -type f -name "*.json" |
  while read -r file; do
    jq -r --arg file_name "$file" --arg key "$KEY" '
    [.usuarios[].servicios[$key]? // [] | .[].consecutivo] |
      if length > 0 then max as $max | "\($file_name) | \($max)"
      else "\($file_name) | 0" end' "$file"
  done
