#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: $0 <path>"
  exit 1
fi

DATA_PATH="$1"

find "$DATA_PATH" -type f -name "*.json" |
  while read -r file; do
    jq -r --arg file_name "$file" '
    [.usuarios[]? // [] | .consecutivo?] |
      if length > 0 then max as $max | "\($file_name) | \($max)"
      else "\($file_name) | 0" end' "$file"
  done
