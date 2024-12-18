#!/bin/bash

# Set default values for bandwidth limits
BW_LIMIT="10000kbps"
IDLE_BW_LIMIT="10000kbps"

# Set default method to 1 if not provided
METHOD=${1:-1}

# Parse optional arguments for bandwidth limits
while getopts "b:i:" opt; do
    case $opt in
        b) BW_LIMIT="$OPTARG"
        ;;
        i) IDLE_BW_LIMIT="$OPTARG"
        ;;
        *) echo "Invalid option"; exit 1
        ;;
    esac
done

shift $((OPTIND - 1))

# Validate the method
if [[ "$METHOD" != "1" && "$METHOD" != "2" ]]; then
    echo "Error: Invalid method. Please specify 1 or 2."
    exit 1
fi

# Extract the database sizes from CSV and convert to MB using Python
DB_SIZES=$(python3 extract_db_size.py)

# Convert the comma-separated string into a Bash array
IFS=',' read -r -a DB_SIZE_ARRAY <<< "$DB_SIZES"

# Loop over each value in the DB_SIZE_ARRAY
for DB_SIZE in "${DB_SIZE_ARRAY[@]}"; do
    if [ "$METHOD" -eq 1 ]; then
        # Run migration.sh for method 1 with dynamic bandwidth limits
        ./migration.sh -s "$DB_SIZE" -x 1M -b "$BW_LIMIT" -i "$IDLE_BW_LIMIT"
    elif [ "$METHOD" -eq 2 ]; then
        # Run migration_v2.sh for method 2 with dynamic bandwidth limits
        ./migration_v2.sh -s "$DB_SIZE" -x 1M -b "$BW_LIMIT" -i "$IDLE_BW_LIMIT"
    fi
done