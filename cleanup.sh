#!/bin/bash

# This script removes trailing whitespace from all .ex and .exs files
# in the lib and test directories.

echo "Searching for files with trailing whitespace..."

find lib test -type f \( -name "*.ex" -o -name "*.exs" \) -print0 | while IFS= read -r -d '' file; do
    sed -i'' -e 's/[[:space:]]\+$//' "$file"
    echo "Cleaned $file"
done

echo "Whitespace cleanup complete."
