#!/bin/bash

# Default values for optional parameters
NETWORK_NAME="mqtt-net"
SUBNET="172.25.0.0/16"
GATEWAY="172.25.0.1"
BROKER_NAME="mqtt-broker"
BROKER_IP="172.25.0.2"
BROKER_MAC="02:42:ac:19:00:02"
CLIENT_NAME="mqtt-client"
CLIENT_IP="172.25.0.3"
CLIENT_MAC="02:42:ac:19:00:03"
IDLE_BROKER_NAME="mqtt-broker2"
IDLE_BROKER_IP="172.25.0.4"
IDLE_BROKER_MAC="02:42:ac:19:00:04"
CUSTOM_BROKER_IMAGE_FIRST="custom_mqtt_broker_first"
CUSTOM_BROKER_IMAGE_SECOND="custom_mqtt_broker_second"
CUSTOM_CLIENT_IMAGE="custom_mqtt_client"

# # Default transfer limits
# SERVER_BW_LIMIT="10bit"
# IDLE_SERVER_BW_LIMIT="10bit"

BW_LIMITS=("3mbit" "27mbit")
# Extract the database sizes from CSV and convert to MB using Python
#DB_SIZES=$(python3 extract_db_size.py)

# Convert the comma-separated string into a Bash array DB_SIZE_ARRAY=(1048576 104857600 1073741824 10737418240)

#IFS=',' read -r -a DB_SIZE_ARRAY <<< "$DB_SIZES"
DB_SIZE_ARRAY=(10485760)

# Loop through all combinations of copy methods and migration methods
COPY_METHODS=("scp" "rsync")
MIGRATION_METHODS=("stop" "dis")

# Loop through all database sizes and run the simulation
for DB_SIZE in "${DB_SIZE_ARRAY[@]}"; do
    for BW_LIMIT in "${BW_LIMITS[@]}"; do
        for COPY_METHOD in "${COPY_METHODS[@]}"; do
            for MIGRATION_METHOD in "${MIGRATION_METHODS[@]}"; do
                echo "Running simulation with DB_SIZE=$DB_SIZE, SERVER_BW_LIMIT=$BW_LIMIT, IDLE_SERVER_BW_LIMIT=$BW_LIMIT, COPY_METHOD=$COPY_METHOD, MIGRATION_METHOD=$MIGRATION_METHOD"
                ./migration_mqtt.sh -s "$DB_SIZE" -b "$BW_LIMIT" -i "$BW_LIMIT" -m "$COPY_METHOD" -t "$MIGRATION_METHOD"
            done
        done
    done
done
