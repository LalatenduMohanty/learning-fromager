#!/bin/bash

# Cleanup script for fromager learning project
# Removes generated files and directories

set -e

echo "Starting cleanup..."

# Remove constraints.txt files
if [ -f "constraints.txt" ]; then
    echo "Removing constraints.txt"
    rm -f constraints.txt
fi

# Remove requirements.txt file (root level)
if [ -f "requirements.txt" ]; then
    echo "Removing requirements.txt"
    rm -f requirements.txt
fi

# Remove directories
for dir in "wheels-repo" "sdists-repo" "work-dir"; do
    if [ -d "$dir" ]; then
        echo "Removing directory: $dir"
        rm -rf "$dir"
    fi
done

echo "Cleanup completed!"
