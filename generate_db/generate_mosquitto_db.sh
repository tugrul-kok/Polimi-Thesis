#!/bin/bash

# Desired database sizes in bytes
DESIRED_SIZES_B=(10485760)
#1048576 104857600 1073741824 102400
OUTPUT_DIR="/Users/tugrul/Desktop/Tez/database_files/databases"

# Mosquitto persistence directory (host directory mounted to /mosquitto/data in Docker)
PERSISTENCE_DIR="/Users/tugrul/Desktop/Tez/database_files/mosquitto_docker/data"

# Mosquitto configuration file (host directory mounted to /mosquitto/config in Docker)
MOSQUITTO_CONF="/Users/tugrul/Desktop/Tez/database_files/mosquitto_docker/config/mosquitto.conf"

# Log file
LOG_FILE="/Users/tugrul/Desktop/Tez/database_files/generate_databases.log"

# Redirect all output to log file
exec > >(tee -i "$LOG_FILE")
exec 2>&1

# Function to start Mosquitto broker using Docker
start_broker() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Mosquitto Docker container..."
  docker start mosquitto1.6 >/dev/null 2>&1

  # Check if the container started successfully
  if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to start Mosquitto Docker container. Attempting to run a new container..."

    # Run a new container if it's not already created
    docker run -d \
      --name mosquitto1.6 \
      -p 1883:1883 \
      -v /Users/tugrul/Desktop/Tez/database_files/mosquitto_docker/config/mosquitto.conf:/mosquitto/config/mosquitto.conf \
      -v /Users/tugrul/Desktop/Tez/database_files/mosquitto_docker/data:/mosquitto/data \
      -v /Users/tugrul/Desktop/Tez/database_files/mosquitto_docker/log:/mosquitto/log \
      eclipse-mosquitto:1.6.9

    # Wait for the broker to initialize
    sleep 5
  else
    # Wait briefly to ensure the broker is ready
    sleep 2
  fi
}

# Function to stop Mosquitto broker using Docker
stop_broker() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Stopping Mosquitto Docker container..."
  docker stop mosquitto1.6 >/dev/null 2>&1
  sleep 2  # Allow time for the broker to stop
}

# Ensure the output directory exists
mkdir -p "$OUTPUT_DIR"

# Trap signals to ensure broker is stopped
trap 'stop_broker; exit 1' INT TERM

for SIZE_B in "${DESIRED_SIZES_B[@]}"; do
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Generating mosquitto.db of size ~${SIZE_B}B"

  # Clean up previous database
  stop_broker
  rm -f "$PERSISTENCE_DIR/mosquitto.db"

  # Start Mosquitto broker
  start_broker

  # Initialize variables
  TARGET_SIZE_B=$SIZE_B
  MESSAGE_COUNT=0
  TOTAL_PAYLOAD_SENT_B=0

  # Publish messages until the total payload sent reaches the target size
  while [ "$TOTAL_PAYLOAD_SENT_B" -lt "$TARGET_SIZE_B" ]; do
    ((MESSAGE_COUNT++))
    PAYLOAD_SIZE_B=$((SIZE_B / 10))  # Adjust payload size as needed (1MB in bytes)

    # Calculate remaining size
    REMAINING_B=$((TARGET_SIZE_B - TOTAL_PAYLOAD_SENT_B))
    if [ "$REMAINING_B" -lt "$PAYLOAD_SIZE_B" ]; then
      PAYLOAD_SIZE_B="$REMAINING_B"
    fi

    # Generate random payload using /dev/urandom
    head -c "$PAYLOAD_SIZE_B" /dev/urandom > payload.bin

    # Publish retained message to the Dockerized Mosquitto broker
    mosquitto_pub -h localhost -p 1883 -t "test/topic/$MESSAGE_COUNT" -r -f payload.bin

    # Remove payload file
    rm -f payload.bin

    # Update total payload sent
    TOTAL_PAYLOAD_SENT_B=$((TOTAL_PAYLOAD_SENT_B + PAYLOAD_SIZE_B))

    # Optional: Display progress
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Published message $MESSAGE_COUNT - Total Payload Sent: ${TOTAL_PAYLOAD_SENT_B}B / ${TARGET_SIZE_B}B"
  done

  # Stop the broker to trigger persistence save
  stop_broker

  # Wait briefly to ensure persistence save is complete
  sleep 2

  # Verify mosquitto.db size
  if [ -f "$PERSISTENCE_DIR/mosquitto.db" ]; then
    CURRENT_SIZE_B=$(du -b "$PERSISTENCE_DIR/mosquitto.db" | cut -f1)
  else
    CURRENT_SIZE_B=0
  fi

  echo "$(date '+%Y-%m-%d %H:%M:%S') - mosquitto.db size after generation: ${CURRENT_SIZE_B}B / ${TARGET_SIZE_B}B"

  # Create output directory for this size
  OUTPUT_SIZE_DIR="$OUTPUT_DIR/${SIZE_B}"
  mkdir -p "$OUTPUT_SIZE_DIR"

  # Copy the database file
  cp "$PERSISTENCE_DIR/mosquitto.db" "$OUTPUT_SIZE_DIR/"

  echo "$(date '+%Y-%m-%d %H:%M:%S') - mosquitto.db of size ~${SIZE_B}B saved to ${OUTPUT_SIZE_DIR}/"
done

echo "$(date '+%Y-%m-%d %H:%M:%S') - All databases generated successfully."
