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

# Usage function to display help for the script
usage() {
    echo "Usage: $0 -s DB_SIZE -x DB_SUFFIX -b BROKER_BW_LIMIT -i IDLE_BROKER_BW_LIMIT [options]"
    echo "  -s DB_SIZE                Size of the fake database (required)"
    echo "  -x DB_SUFFIX              Suffix for DB_SIZE (e.g., M for MB) (required)"
    echo "  -b BROKER_BW_LIMIT        Bandwidth limit for the broker (required)"
    echo "  -i IDLE_BROKER_BW_LIMIT   Bandwidth limit for the idle broker (required)"
    echo "  Optional parameters:"
    echo "  -n NETWORK_NAME           Docker network name (default: mqtt-net)"
    echo "  -c CLIENT_NAME            Client container name (default: mqtt-client)"
    exit 1
}

# Parse command-line arguments
while getopts "s:x:b:i:n:c:" opt; do
    case "${opt}" in
        s)
            DB_SIZE=${OPTARG}
            ;;
        x)
            DB_SUFFIX=${OPTARG}
            ;;
        b)
            BROKER_BW_LIMIT=${OPTARG}
            ;;
        i)
            IDLE_BROKER_BW_LIMIT=${OPTARG}
            ;;
        n)
            NETWORK_NAME=${OPTARG}
            ;;
        c)
            CLIENT_NAME=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done

# Ensure mandatory parameters are provided
if [ -z "$DB_SIZE" ] || [ -z "$DB_SUFFIX" ] || [ -z "$BROKER_BW_LIMIT" ] || [ -z "$IDLE_BROKER_BW_LIMIT" ]; then
    echo "Error: Missing required arguments."
    usage
fi

# Construct the log directory path based on the provided arguments
LOG_DIR="logs/${DB_SIZE}M_${BROKER_BW_LIMIT}_${IDLE_BROKER_BW_LIMIT}"
mkdir -p $LOG_DIR

# Proceed with the rest of the script using the parsed variables
echo "DB_SIZE: $DB_SIZE"
echo "DB_SUFFIX: $DB_SUFFIX"
echo "BROKER_BW_LIMIT: $BROKER_BW_LIMIT"
echo "IDLE_BROKER_BW_LIMIT: $IDLE_BROKER_BW_LIMIT"
echo "NETWORK_NAME: $NETWORK_NAME"
echo "CLIENT_NAME: $CLIENT_NAME"
echo "Logs directory: $LOG_DIR"

# Function to limit bandwidth inside a container
limit_bandwidth() {
    CONTAINER_NAME=$1
    INTERFACE=$2
    RATE=$3
    docker exec $CONTAINER_NAME tc qdisc add dev $INTERFACE root tbf rate $RATE latency 50ms burst 1540
    echo "Applied bandwidth limit of $RATE on $CONTAINER_NAME ($INTERFACE)"
}

# Function to remove bandwidth limits inside a container
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
docker volume rm second_broker_db_volume 2>/dev/null
rm fake_database.db 2>/dev/null

# Adjust the size of the db file
dd if=/dev/urandom of=fake_database.db bs=$DB_SUFFIX count=$DB_SIZE
sleep 3

# Create Docker network
docker network create --subnet=$SUBNET --gateway=$GATEWAY $NETWORK_NAME

# Build custom Docker images
echo "Building custom Docker images..."
docker build -t $CUSTOM_BROKER_IMAGE_FIRST -f Dockerfile.first .
docker build -t $CUSTOM_BROKER_IMAGE_SECOND -f Dockerfile.second .
docker build -t $CUSTOM_CLIENT_IMAGE -f Dockerfile.client .

# Create a Docker volume for the second broker's database
docker volume create second_broker_db_volume

# Run active MQTT broker container (First Broker)
docker run -d --name $BROKER_NAME \
    --cap-add=NET_ADMIN \
    --network $NETWORK_NAME \
    --ip $BROKER_IP \
    --mac-address $BROKER_MAC \
    $CUSTOM_BROKER_IMAGE_FIRST

# Run idle MQTT broker container (Second Broker) with the database volume
docker run -d --name $IDLE_BROKER_NAME \
    --cap-add=NET_ADMIN \
    --network $NETWORK_NAME \
    --ip $IDLE_BROKER_IP \
    --mac-address $IDLE_BROKER_MAC \
    -v second_broker_db_volume:/app \
    $CUSTOM_BROKER_IMAGE_SECOND

# Wait a moment to ensure the brokers start
sleep 5

# Run MQTT client container with reconnect logic and downtime measurement
docker run -d --name $CLIENT_NAME \
    --network $NETWORK_NAME \
    --ip $CLIENT_IP \
    --mac-address $CLIENT_MAC \
    -e BROKER_IP=$BROKER_IP \
    -v $(pwd)/$LOG_DIR:/logs \
    $CUSTOM_CLIENT_IMAGE \
    -c "END_TIME=\$((\$(date +%s) + 300)); \
        connected=true; \
        DOWNTIME_TOTAL=0; \
        while [ \$(date +%s) -lt \$END_TIME ]; do \
            echo \"Starting MQTT client at \$(date)\"; \
            mosquitto_pub -h \$BROKER_IP -t 'test/topic' -m 'Test message'; \
            EXIT_CODE=\$?; \
            if [ \$EXIT_CODE -ne 0 ]; then \
                if [ \"\$connected\" = true ]; then \
                    DISCONNECT_TIME=\$(date +%s); \
                    echo \"Disconnected at \$(date)\" >> /logs/downtime_log.txt; \
                    connected=false; \
                fi; \
            else \
                if [ \"\$connected\" = false ]; then \
                    RECONNECT_TIME=\$(date +%s); \
                    DOWNTIME=\$((RECONNECT_TIME - DISCONNECT_TIME)); \
                    DOWNTIME_TOTAL=\$((DOWNTIME_TOTAL + DOWNTIME)); \
                    echo \"Reconnected at \$(date) after \$DOWNTIME seconds of downtime\" >> /logs/downtime_log.txt; \
                    connected=true; \
                fi; \
            fi; \
            echo \"MQTT publish ended at \$(date)\"; \
            sleep 1; \
        done; \
        if [ \"\$connected\" = false ]; then \
            echo \"Client did not reconnect before the end of the test.\" >> /logs/downtime_log.txt; \
        fi; \
        echo \"Total downtime: \$DOWNTIME_TOTAL seconds\" >> /logs/downtime_log.txt; \
        echo \$DOWNTIME_TOTAL > /logs/downtime_total.txt; \
        sync /logs/downtime_total.txt;"  # Ensure the file is flushed properly

echo "MQTT brokers and client are running."

# Allow the test to run for 30 seconds before migration
sleep 30

echo "Migrating the broker from $BROKER_NAME to $IDLE_BROKER_NAME..."

# Save logs of the first broker before stopping it
docker logs --timestamps $BROKER_NAME > $LOG_DIR/broker_log_before_migration.txt

# Start timing of SSH setup in milliseconds
START_TIME_SSH_SETUP=$(python3 -c 'import time; print(int(time.time() * 1000))')

# Apply bandwidth limit to the first broker's network interface
limit_bandwidth $BROKER_NAME eth0 $BROKER_BW_LIMIT

# Apply bandwidth limit to the second broker's network interface (if needed)
limit_bandwidth $IDLE_BROKER_NAME eth0 $IDLE_BROKER_BW_LIMIT

# Copy the database file from the first broker to the second broker using scp
echo "Copying database file from $BROKER_NAME to $IDLE_BROKER_NAME over the network..."

# Copy SSH key from the first broker to the second broker to enable passwordless SSH
docker exec $BROKER_NAME ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
PUB_KEY=$(docker exec $BROKER_NAME cat /root/.ssh/id_rsa.pub)
docker exec $IDLE_BROKER_NAME mkdir -p /root/.ssh
docker exec $IDLE_BROKER_NAME sh -c "echo '$PUB_KEY' >> /root/.ssh/authorized_keys"

# Update known_hosts in the first broker to avoid SSH prompts
docker exec $BROKER_NAME sh -c "ssh-keyscan -H $IDLE_BROKER_IP >> /root/.ssh/known_hosts"

# End timing of SSH setup
END_TIME_SSH_SETUP=$(python3 -c 'import time; print(int(time.time() * 1000))')

# Calculate duration of SSH setup in milliseconds
SSH_SETUP_DURATION_MS=$(($END_TIME_SSH_SETUP - $START_TIME_SSH_SETUP))

# Output the duration
echo "SSH setup duration: $SSH_SETUP_DURATION_MS milliseconds"
echo "SSH setup duration: $SSH_SETUP_DURATION_MS milliseconds" >> $LOG_DIR/timings_log.txt

# Start timing of scp command
START_TIME_SCP=$(python3 -c 'import time; print(int(time.time() * 1000))')

# Perform the scp command from the first broker to the second broker
docker exec $BROKER_NAME scp ./fake_database.db root@$IDLE_BROKER_IP:/app/fake_database.db

# End timing of scp command
END_TIME_SCP=$(python3 -c 'import time; print(int(time.time() * 1000))')

# Calculate duration of scp command in milliseconds
SCP_DURATION_MS=$(($END_TIME_SCP - $START_TIME_SCP))

# Output the duration
echo "SCP command duration: $SCP_DURATION_MS milliseconds"
echo "SCP command duration: $SCP_DURATION_MS milliseconds" >> $LOG_DIR/timings_log.txt

# Remove bandwidth limits
remove_bandwidth_limit $BROKER_NAME eth0
remove_bandwidth_limit $IDLE_BROKER_NAME eth0

# Stop and remove the first broker container
docker stop $BROKER_NAME
docker rm $BROKER_NAME

# Stop and remove the idle broker container
docker stop $IDLE_BROKER_NAME
docker rm $IDLE_BROKER_NAME

# Start the second broker with the IP and MAC of the first broker, mounting the same volume
docker run -d --name $IDLE_BROKER_NAME \
    --cap-add=NET_ADMIN \
    --network $NETWORK_NAME \
    --ip $BROKER_IP \
    --mac-address $BROKER_MAC \
    -v second_broker_db_volume:/app \
    $CUSTOM_BROKER_IMAGE_SECOND

echo "Broker migration complete."

# Allow the test to continue for the remaining time
sleep 30

# Save logs of the second broker after migration
docker logs --timestamps $IDLE_BROKER_NAME > $LOG_DIR/broker_log_after_migration.txt

# Save client logs
docker logs --timestamps $CLIENT_NAME > $LOG_DIR/client_log.txt

echo "Logs are stored in the '$LOG_DIR' directory."

# Wait for the client to finish and capture the downtime
echo "Waiting for client container to finish..."
docker wait $CLIENT_NAME

# Read total downtime from the downtime_total.txt file
DOWNTIME_TOTAL=$(cat $LOG_DIR/downtime_total.txt 2>/dev/null)

# Check if DOWNTIME_TOTAL was captured correctly
if [ -z "$DOWNTIME_TOTAL" ]; then
    DOWNTIME_TOTAL=0
    echo "Warning: Downtime not captured, setting to 0."
else
    echo "Total downtime: $DOWNTIME_TOTAL seconds"
fi

# Create/append results to CSV file
CSV_FILE="results.csv"
if [ ! -f "$CSV_FILE" ]; then
    echo "DB_SIZE,DB_SUFFIX,BROKER_BW_LIMIT,IDLE_BROKER_BW_LIMIT,SSH_SETUP_DURATION_MS,SCP_DURATION_MS,DOWNTIME_SECONDS" > $CSV_FILE
fi
echo "$DB_SIZE,$DB_SUFFIX,$BROKER_BW_LIMIT,$IDLE_BROKER_BW_LIMIT,$SSH_SETUP_DURATION_MS,$SCP_DURATION_MS,$DOWNTIME_TOTAL" >> $CSV_FILE

echo "Simulation results appended to $CSV_FILE"

# Clean up after the test
echo "Cleaning up containers and network..."
docker stop $CLIENT_NAME $IDLE_BROKER_NAME
docker rm $CLIENT_NAME $IDLE_BROKER_NAME
docker network rm $NETWORK_NAME
docker volume rm second_broker_db_volume

