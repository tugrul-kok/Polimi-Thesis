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

# Default copy method (SCP)
COPY_METHOD="scp"

# Default transfer method (stop)
MIGRATION_METHOD="stop"

# Path to database files
DATABASE_DIR="/Users/tugrul/Desktop/Tez/database_files/databases"

# Usage function to display help for the script
usage() {
    echo "Usage: $0 -s DB_SIZE -b SERVER_BW_LIMIT -i IDLE_SERVER_BW_LIMIT [-m COPY_METHOD] [options]"
    echo "  -s DB_SIZE                Size of the mosquitto.db to use initially (e.g., '1MB') (required)"
    echo "  -b SERVER_BW_LIMIT        Bandwidth limit for the server broker (e.g., '1mbit') (required)"
    echo "  -i IDLE_SERVER_BW_LIMIT   Bandwidth limit for the idle broker (e.g., '1mbit') (required)"
    echo "  Optional parameters:"
    echo "  -n NETWORK_NAME           Docker network name (default: mqtt-net)"
    echo "  -c CLIENT_NAME            Client container name (default: mqtt-client)"
    echo "  -m COPY_METHOD            Copy method to use: 'scp' or 'rsync' (default: scp)"
    echo "  -t MIGRATION_METHOD        Transfer method to use: 'stop' or 'dis' (default: stop)"

    exit 1
}

# Parse command-line arguments
while getopts "s:b:i:n:c:m:t:" opt; do
    case "${opt}" in
        s)
            DB_SIZE=${OPTARG}
            ;;
        b)
            SERVER_BW_LIMIT=${OPTARG}
            ;;
        i)
            IDLE_SERVER_BW_LIMIT=${OPTARG}
            ;;
        n)
            NETWORK_NAME=${OPTARG}
            ;;
        c)
            CLIENT_NAME=${OPTARG}
            ;;
        m)
            COPY_METHOD=${OPTARG}
            if [[ "$COPY_METHOD" != "scp" && "$COPY_METHOD" != "rsync" ]]; then
                echo "Invalid copy method: $COPY_METHOD. Use 'scp' or 'rsync'."
                exit 1
            fi
            ;;
        t)
            MIGRATION_METHOD=${OPTARG}
            if [[ "$MIGRATION_METHOD" != "stop" && "$MIGRATION_METHOD" != "dis" ]]; then
                echo "Invalid transfer method: $MIGRATION_METHOD. Use 'stop' or 'dis'."
                exit 1
            fi
            ;;        
        *)
            usage
            ;;
    esac
done

# Check if required parameters are provided
if [ -z "$DB_SIZE" ] || [ -z "$SERVER_BW_LIMIT" ] || [ -z "$IDLE_SERVER_BW_LIMIT" ]; then
    echo "Error: Missing required arguments."
    usage
fi

# Construct the log directory path
LOG_DIR="logs/${DB_SIZE}B_${COPY_METHOD}_${MIGRATION_METHOD}_BW_${SERVER_BW_LIMIT}_IdleBW_${IDLE_SERVER_BW_LIMIT}"
mkdir -p $LOG_DIR
chmod 777 $LOG_DIR

# Define path to the initial database file
INITIAL_DB_FILE="${DATABASE_DIR}/${DB_SIZE}/mosquitto.db"

# Check if the database file exists
if [ ! -f "$INITIAL_DB_FILE" ]; then
    echo "Error: Database file '$INITIAL_DB_FILE' not found."
    exit 1
fi

# Proceed with the rest of the script using the parsed variables
echo "DB_SIZE: $DB_SIZE"
echo "SERVER_BW_LIMIT: $SERVER_BW_LIMIT"
echo "IDLE_SERVER_BW_LIMIT: $IDLE_SERVER_BW_LIMIT"
echo "NETWORK_NAME: $NETWORK_NAME"
echo "CLIENT_NAME: $CLIENT_NAME"
echo "Logs directory: $LOG_DIR"

# Function to limit bandwidth inside a container (if needed)
limit_bandwidth() {
    CONTAINER_NAME=$1
    INTERFACE=$2
    RATE=$3
    docker exec $CONTAINER_NAME tc qdisc add dev $INTERFACE root tbf rate $RATE latency 50ms burst 1540
    echo "Applied bandwidth limit of $RATE on $CONTAINER_NAME ($INTERFACE)"
}

# Function to remove bandwidth limits inside a container (if needed)
remove_bandwidth_limit() {
    CONTAINER_NAME=$1
    INTERFACE=$2
    docker exec $CONTAINER_NAME tc qdisc del dev $INTERFACE root
    echo "Removed bandwidth limit on $CONTAINER_NAME ($INTERFACE)"
}

# Clean up any existing containers, networks, volumes, and directories
echo "Cleaning up existing containers, networks, volumes, and directories..."
docker rm -f $CLIENT_NAME $BROKER_NAME $IDLE_BROKER_NAME 2>/dev/null
docker network rm $NETWORK_NAME 2>/dev/null
docker volume rm mosquitto_data_volume mosquitto_data_volume_second 2>/dev/null
rm -rf ./mosquitto.db 2>/dev/null

# Create Docker network
docker network create --subnet=$SUBNET --gateway=$GATEWAY $NETWORK_NAME

# Build custom Docker images
echo "Building custom Docker images..."
docker build -t $CUSTOM_BROKER_IMAGE_FIRST -f Dockerfile.broker .
docker build -t $CUSTOM_BROKER_IMAGE_SECOND -f Dockerfile.broker .
docker build -t $CUSTOM_CLIENT_IMAGE -f Dockerfile.client .

# Create Docker volumes for Mosquitto persistence
docker volume create mosquitto_data_volume
docker volume create mosquitto_data_volume_second

# Copy the initial mosquitto.db file to a temporary location
cp "$INITIAL_DB_FILE" ./mosquitto.db

# Run active MQTT broker container (First Broker)
docker run -d --name $BROKER_NAME \
    --cap-add=NET_ADMIN \
    --network $NETWORK_NAME \
    --ip $BROKER_IP \
    --mac-address $BROKER_MAC \
    -v mosquitto_data_volume:/mosquitto/data/ \
    --memory=2g \
    --memory-swap=6g \
    $CUSTOM_BROKER_IMAGE_FIRST

# Wait a moment to ensure the broker starts
sleep 5

# Stop the broker to copy the mosquitto.db file safely
docker stop $BROKER_NAME

# Copy the initial mosquitto.db file into the first broker's data volume
docker cp ./mosquitto.db $BROKER_NAME:/mosquitto/data/mosquitto.db

# Ensure the ownership of mosquitto.db file is set correctly for Mosquitto
docker start $BROKER_NAME
docker exec $BROKER_NAME chown mosquitto:mosquitto /mosquitto/data/mosquitto.db

# Run idle MQTT broker container (Second Broker) with its own data volume
docker run -d --name $IDLE_BROKER_NAME \
    --cap-add=NET_ADMIN \
    --network $NETWORK_NAME \
    --ip $IDLE_BROKER_IP \
    --mac-address $IDLE_BROKER_MAC \
    -v mosquitto_data_volume_second:/mosquitto/data/ \
    --memory=2g \
    --memory-swap=6g \
    $CUSTOM_BROKER_IMAGE_SECOND

# Wait a moment to ensure the brokers start
sleep 5

# Run MQTT client container
docker run -d --name $CLIENT_NAME \
    --network $NETWORK_NAME \
    --ip $CLIENT_IP \
    --mac-address $CLIENT_MAC \
    -e BROKER_IP=$BROKER_IP \
    -v $(pwd)/$LOG_DIR:/logs \
    $CUSTOM_CLIENT_IMAGE

echo "MQTT brokers and client are running."

# Allow the test to run for 30 seconds before migration
sleep 10



# Apply bandwidth limits to the brokers
# limit_bandwidth $BROKER_NAME eth0 $SERVER_BW_LIMIT
# limit_bandwidth $IDLE_BROKER_NAME eth0 $IDLE_SERVER_BW_LIMIT

# Start timing of SSH setup
START_TIME_SSH_SETUP=$(python3 -c 'import time; print(int(time.time() * 1000))')

# Set up SSH between brokers
echo "Setting up SSH between brokers..."

# Generate SSH keys on the first broker
docker exec $BROKER_NAME ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa

# Get the public key
PUB_KEY=$(docker exec $BROKER_NAME cat /root/.ssh/id_rsa.pub)

# Add the public key to the authorized_keys on the second broker
docker exec $IDLE_BROKER_NAME mkdir -p /root/.ssh
docker exec $IDLE_BROKER_NAME sh -c "echo '$PUB_KEY' >> /root/.ssh/authorized_keys"

# Update known_hosts on the first broker to avoid SSH prompts
docker exec $BROKER_NAME sh -c "ssh-keyscan -H $IDLE_BROKER_IP >> /root/.ssh/known_hosts"

# End timing of SSH setup
END_TIME_SSH_SETUP=$(python3 -c 'import time; print(int(time.time() * 1000))')

# Calculate duration of SSH setup in milliseconds
SSH_SETUP_DURATION_MS=$(($END_TIME_SSH_SETUP - $START_TIME_SSH_SETUP))

# Output the duration
echo "SSH setup duration: $SSH_SETUP_DURATION_MS milliseconds"
echo "SSH setup duration: $SSH_SETUP_DURATION_MS milliseconds" >> $LOG_DIR/timings_log.txt



# Save logs of the first broker before stopping Mosquitto
docker logs --timestamps $BROKER_NAME > $LOG_DIR/broker_log_before_migration.txt

# Gracefully stop the Mosquitto service inside the first broker
docker exec $BROKER_NAME pkill mosquitto
# Wait for mosquitto to be stopped
#sleep 1
limit_bandwidth $BROKER_NAME eth0 $SERVER_BW_LIMIT
limit_bandwidth $IDLE_BROKER_NAME eth0 $IDLE_SERVER_BW_LIMIT

echo "Migrating the broker from $BROKER_NAME to $IDLE_BROKER_NAME..."
START_TIME_MIGRATION=$(python3 -c 'import time; print(int(time.time() * 1000))')
echo "mosquitto stopped"

# Get the size of mosquitto.db before transmission
MOSQUITTO_DB_SIZE=$(docker  exec $BROKER_NAME du -b /mosquitto/data/mosquitto.db | cut -f1)
echo "mosquitto.db size: $MOSQUITTO_DB_SIZE bytes"
echo "mosquitto.db size: $MOSQUITTO_DB_SIZE bytes" >> $LOG_DIR/timings_log.txt


# Start timing of the copy command (SCP or RSYNC)
START_TIME_COPY=$(python3 -c 'import time; print(int(time.time() * 1000))')

# Choose between SCP and RSYNC for the file transfer
if [ "$COPY_METHOD" == "scp" ]; then
    echo "Copying mosquitto.db from $BROKER_NAME to $IDLE_BROKER_NAME using SCP..."
    docker exec $BROKER_NAME scp /mosquitto/data/mosquitto.db root@$IDLE_BROKER_IP:/mosquitto/data/mosquitto.db
else
    echo "Copying mosquitto.db from $BROKER_NAME to $IDLE_BROKER_NAME using RSYNC..."
    docker exec $BROKER_NAME rsync -av --no-inc-recursive --progress \
    -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
    /mosquitto/data/mosquitto.db root@$IDLE_BROKER_IP:/mosquitto/data/mosquitto.db \
    2>&1 | tee $LOG_DIR/rsync_output.txt
fi

# End timing of the copy command
END_TIME_COPY=$(python3 -c 'import time; print(int(time.time() * 1000))')

# Calculate duration of the copy command in milliseconds
COPY_DURATION_MS=$(($END_TIME_COPY - $START_TIME_COPY))

# Output the duration
echo "Copy command duration: $COPY_DURATION_MS milliseconds"
echo "Copy command duration: $COPY_DURATION_MS milliseconds" >> $LOG_DIR/timings_log.txt

# Remove bandwidth limits
remove_bandwidth_limit $BROKER_NAME eth0
remove_bandwidth_limit $IDLE_BROKER_NAME eth0

# if MIGRATION_METHOD is 'dis', stop the first broker and start the second broker
if [ "$MIGRATION_METHOD" == "dis" ]; then
    SERVER_MIGRATING_START=$(python3 -c 'import time; print(int(time.time() * 1000))')
    # Disconnect the first server from the network
    echo "Disconnecting $BROKER_NAME (first server) from the network..."
    docker network disconnect $NETWORK_NAME $BROKER_NAME

    # Disconnecting the second server from the network
    echo "Disconnecting $IDLE_BROKER_NAME (second server) from the network..."
    docker network disconnect $NETWORK_NAME $IDLE_BROKER_NAME

    # Reconnect the second server with the IP and MAC of the first server
    echo "Reconnecting $IDLE_BROKER_NAME (second server) with the IP and MAC of $s BROKER_NAME..."
    docker network connect --ip $BROKER_IP $NETWORK_NAME $IDLE_BROKER_NAME
    SERVER_MIGRATING_END=$(python3 -c 'import time; print(int(time.time() * 1000))')
    END_TIME_MIGRATION=$(python3 -c 'import time; print(int(time.time() * 1000))')

fi

# if MIGRATION_METHOD is 'stop', stop the second broker and start the first broker
if [ "$MIGRATION_METHOD" == "stop" ]; then
    SERVER_MIGRATING_START=$(python3 -c 'import time; print(int(time.time() * 1000))')
    # Stop and remove the broker
    docker stop $BROKER_NAME
    docker rm $BROKER_NAME

    # Stop and remove the idle broker
    docker stop $IDLE_BROKER_NAME
    docker rm $IDLE_BROKER_NAME

    # Start the second broker with the IP and MAC of the first broker
    docker run -d --name $IDLE_BROKER_NAME \
        --cap-add=NET_ADMIN \
        --network $NETWORK_NAME \
        --ip $BROKER_IP \
        --mac-address $BROKER_MAC \
        -v mosquitto_data_volume_second:/mosquitto/data/ \
        --memory=2g \
        --memory-swap=6g \
        $CUSTOM_BROKER_IMAGE_SECOND

    SERVER_MIGRATING_END=$(python3 -c 'import time; print(int(time.time() * 1000))')
    END_TIME_MIGRATION=$(python3 -c 'import time; print(int(time.time() * 1000))')


fi

 # Set correct ownership of mosquitto.db in the second broker
docker exec $IDLE_BROKER_NAME chown mosquitto:mosquitto /mosquitto/data/mosquitto.db


SERVER_MIGRATION_DURATION=$(($SERVER_MIGRATING_END - $SERVER_MIGRATING_START))
MIGRATION_DURATION_MS=$(($END_TIME_MIGRATION - $START_TIME_MIGRATION))

echo "Broker migration complete."

# Allow the test to continue for the remaining time
sleep 30

# Save logs of the second broker after migration
docker logs --timestamps $IDLE_BROKER_NAME > $LOG_DIR/broker_log_after_migration.txt

# Path to downtime_log.txt
DOWNTIME_LOG="${LOG_DIR}/downtime_log.txt"

# Read the last logged downtime from the log file
DOWNTIME_TOTAL=$(grep "after" "$DOWNTIME_LOG" | tail -1 | awk '{print $6}')

# Print the value to check
echo "The last recorded downtime was: $DOWNTIME_TOTAL seconds"


# Check if DOWNTIME_TOTAL was captured correctly
if [ -z "$DOWNTIME_TOTAL" ]; then
    DOWNTIME_TOTAL=0
    echo "Warning: Downtime not captured, setting to 0."
else
    echo "Total downtime: $DOWNTIME_TOTAL seconds"
fi

docker logs --timestamps $CLIENT_NAME > $LOG_DIR/client_log.txt

echo "Logs are stored in the '$LOG_DIR' directory."


# Create/append results to CSV file
CSV_FILE="results.csv"
if [ ! -f "$CSV_FILE" ]; then
    # Create the CSV header with the new structure
    echo "MOSQUITTO_DB_SIZE_BYTES,SERVER_BW_LIMIT,IDLE_SERVER_BW_LIMIT,SSH_SETUP_DURATION_MS,TRANSFER_TIME_MS,TRANSFER_METHOD,MIGRATION_METHOD,DOWNTIME_SECONDS,MIGRATION_DURATION,SERVER_MIGRATION_DURATION" > $CSV_FILE
fi

# Log the transfer method (either scp or rsync) and transfer time (TRANSFER_TIME_MS)
TRANSFER_METHOD=$COPY_METHOD
TRANSFER_TIME_MS=$COPY_DURATION_MS

# Append the results to the CSV file
echo "$MOSQUITTO_DB_SIZE,$SERVER_BW_LIMIT,$IDLE_SERVER_BW_LIMIT,$SSH_SETUP_DURATION_MS,$TRANSFER_TIME_MS,$TRANSFER_METHOD,$MIGRATION_METHOD,$DOWNTIME_TOTAL,$MIGRATION_DURATION_MS,$SERVER_MIGRATION_DURATION" >> $CSV_FILE

echo "Simulation results appended to $CSV_FILE"

# Clean up after the test
echo "Cleaning up containers and network..."
docker stop $CLIENT_NAME $IDLE_BROKER_NAME $BROKER_NAME
docker rm $CLIENT_NAME $IDLE_BROKER_NAME $BROKER_NAME
docker network rm $NETWORK_NAME
docker volume rm mosquitto_data_volume mosquitto_data_volume_second

# Clean up temporary files
rm ./mosquitto.db 2>/dev/null

echo "Simulation complete."
