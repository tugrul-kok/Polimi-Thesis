#!/bin/bash

# Extract the database sizes from CSV and convert to MB using Python
DB_SIZES=$(python3 extract_db_size.py)

# Convert the comma-separated string into a Bash array
IFS=',' read -r -a DB_SIZE_ARRAY <<< "$DB_SIZES"

# Loop over each value in the DB_SIZE_ARRAY
for DB_SIZE in "${DB_SIZE_ARRAY[@]}"; do
    ./migration.sh -s DB_SIZE -x 1M -b 1000kbps -i 1000kbps
done