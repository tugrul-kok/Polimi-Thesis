#!/bin/bash

# Desired database sizes in megabytes
DESIRED_SIZES_MB=(1 2 3 4 5)

# Directory to save the generated databases
OUTPUT_DIR="/Users/tugrul/Desktop/Tez/database_files/databases"

# Mosquitto persistence directory
PERSISTENCE_DIR="/Users/tugrul/Desktop/Tez/database_files/mosquitto"

# Mosquitto configuration file
MOSQUITTO_CONF="/Users/tugrul/Desktop/Tez/database_files/mosquitto/mosquitto.conf"

# Function to start Mosquitto broker
start_broker() {
  mosquitto -c "$MOSQUITTO_CONF" -d
  sleep 2  # Allow time for the broker to start
}

# Function to stop Mosquitto broker
stop_broker() {
  pkill mosquitto
  sleep 2  # Allow time for the broker to stop
}

# Ensure the output directory exists
mkdir -p "$OUTPUT_DIR"

for SIZE_MB in "${DESIRED_SIZES_MB[@]}"; do
  echo "Generating mosquitto.db of size ~${SIZE_MB}MB"

  # Clean up previous database
  stop_broker
  rm -f "$PERSISTENCE_DIR/mosquitto.db"

  # Start Mosquitto broker
  start_broker

  # Initialize variables
  CURRENT_SIZE_KB=0
  TARGET_SIZE_KB=$((SIZE_MB * 1024))
  MESSAGE_COUNT=0

  # Publish messages until the database reaches the desired size
  while [ -n "$CURRENT_SIZE_KB" ] && [ "$CURRENT_SIZE_KB" -lt "$TARGET_SIZE_KB" ]; do
    ((MESSAGE_COUNT++))
    PAYLOAD_SIZE_KB=5  # Adjust payload size as needed

    # Generate random payload using openssl
    openssl rand -base64 $((PAYLOAD_SIZE_KB * 1024)) > payload.txt

    # Publish retained message
    mosquitto_pub -t "test/topic/$MESSAGE_COUNT" -r -f payload.txt

    # Remove payload file
    rm payload.txt

    # Signal Mosquitto to save the database
    mosquitto_pid=$(pgrep mosquitto)
    if [ -n "$mosquitto_pid" ]; then
      kill -USR1 "$mosquitto_pid"
    fi

    # Wait briefly to allow Mosquitto to save the database
    sleep 0.5

    # Update current database size
    if [ -f "$PERSISTENCE_DIR/mosquitto.db" ]; then
      CURRENT_SIZE_KB=$(du -k "$PERSISTENCE_DIR/mosquitto.db" | cut -f1)
    else
      CURRENT_SIZE_KB=0
    fi

    # Optional: Display progress
    echo "Published message $MESSAGE_COUNT - DB size: ${CURRENT_SIZE_KB}KB / ${TARGET_SIZE_KB}KB"
  done

  # Stop the broker
  stop_broker

  # Create output directory for this size
  OUTPUT_SIZE_DIR="$OUTPUT_DIR/${SIZE_MB}MB"
  mkdir -p "$OUTPUT_SIZE_DIR"

  # Copy the database file
  cp "$PERSISTENCE_DIR/mosquitto.db" "$OUTPUT_SIZE_DIR/"

  echo "mosquitto.db of size ~${SIZE_MB}MB saved to ${OUTPUT_SIZE_DIR}/"

done

echo "All databases generated successfully."
