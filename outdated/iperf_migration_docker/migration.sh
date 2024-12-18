#!/bin/bash

# Default values for optional parameters
NETWORK_NAME="iperf-net"
SUBNET="172.25.0.0/16"
GATEWAY="172.25.0.1"
SERVER_NAME="iperf-server"
SERVER_IP="172.25.0.2"
SERVER_MAC="02:42:ac:19:00:02"
CLIENT_NAME="iperf-client"
CLIENT_IP="172.25.0.3"
CLIENT_MAC="02:42:ac:19:00:03"
IDLE_SERVER_NAME="iperf-server2"
IDLE_SERVER_IP="172.25.0.4"
IDLE_SERVER_MAC="02:42:ac:19:00:04"
CUSTOM_SERVER_IMAGE_FIRST="custom_iperf_server_first"
CUSTOM_SERVER_IMAGE_SECOND="custom_iperf_server_second"
CUSTOM_CLIENT_IMAGE="custom_iperf_client"

# Usage function to display help for the script
usage() {
    echo "Usage: $0 -s DB_SIZE -x DB_SUFFIX -b SERVER_BW_LIMIT -i IDLE_SERVER_BW_LIMIT [options]"
    echo "  -s DB_SIZE                Size of the fake database (required)"
    echo "  -x DB_SUFFIX              Suffix for DB_SIZE (e.g., M for MB) (required)"
    echo "  -b SERVER_BW_LIMIT        Bandwidth limit for the server (required)"
    echo "  -i IDLE_SERVER_BW_LIMIT   Bandwidth limit for the idle server (required)"
    echo "  Optional parameters:"
    echo "  -n NETWORK_NAME           Docker network name (default: iperf-net)"
    echo "  -c CLIENT_NAME            Client container name (default: iperf-client)"
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
        *)
            usage
            ;;
    esac
done

# Ensure mandatory parameters are provided
if [ -z "$DB_SIZE" ] || [ -z "$DB_SUFFIX" ] || [ -z "$SERVER_BW_LIMIT" ] || [ -z "$IDLE_SERVER_BW_LIMIT" ]; then
    echo "Error: Missing required arguments."
    usage
fi

# Construct the log directory path based on the provided arguments
#LOG_DIR="logs/${DB_SIZE}_${DB_SUFFIX}_${SERVER_BW_LIMIT}_${IDLE_SERVER_BW_LIMIT}"
LOG_DIR="logs/${DB_SIZE}M_${SERVER_BW_LIMIT}_${IDLE_SERVER_BW_LIMIT}"
mkdir -p $LOG_DIR

# Proceed with the rest of the script using the parsed variables
echo "DB_SIZE: $DB_SIZE"
echo "DB_SUFFIX: $DB_SUFFIX"
echo "SERVER_BW_LIMIT: $SERVER_BW_LIMIT"
echo "IDLE_SERVER_BW_LIMIT: $IDLE_SERVER_BW_LIMIT"
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
docker rm -f $CLIENT_NAME $SERVER_NAME $IDLE_SERVER_NAME 2>/dev/null
docker network rm $NETWORK_NAME 2>/dev/null
docker volume rm second_server_db_volume 2>/dev/null
rm fake_database.db 2>/dev/null

# Adjust the size of the db file
dd if=/dev/urandom of=fake_database.db bs=$DB_SUFFIX count=$DB_SIZE
sleep 1

# Create Docker network
docker network create --subnet=$SUBNET --gateway=$GATEWAY $NETWORK_NAME

# Build custom Docker images
echo "Building custom Docker images..."
docker build -t $CUSTOM_SERVER_IMAGE_FIRST -f Dockerfile.first .
docker build -t $CUSTOM_SERVER_IMAGE_SECOND -f Dockerfile.second .
docker build -t $CUSTOM_CLIENT_IMAGE -f Dockerfile.client .

# Create a Docker volume for the second server's database
docker volume create second_server_db_volume

# Run active iperf3 server container (First Server)
docker run -d --name $SERVER_NAME \
    --cap-add=NET_ADMIN \
    --network $NETWORK_NAME \
    --ip $SERVER_IP \
    --mac-address $SERVER_MAC \
    $CUSTOM_SERVER_IMAGE_FIRST

# Run idle iperf3 server container (Second Server) with the database volume
docker run -d --name $IDLE_SERVER_NAME \
    --cap-add=NET_ADMIN \
    --network $NETWORK_NAME \
    --ip $IDLE_SERVER_IP \
    --mac-address $IDLE_SERVER_MAC \
    -v second_server_db_volume:/app \
    $CUSTOM_SERVER_IMAGE_SECOND

# Wait a moment to ensure the servers start
sleep 5

# Run iperf3 client container with reconnect logic and downtime measurement
docker run -d --name $CLIENT_NAME \
    --network $NETWORK_NAME \
    --ip $CLIENT_IP \
    --mac-address $CLIENT_MAC \
    -e SERVER_IP=$SERVER_IP \
    -v $(pwd)/$LOG_DIR:/logs \
    $CUSTOM_CLIENT_IMAGE \
    -c "END_TIME=\$((\$(date +%s) + 300)); \
        connected=true; \
        while [ \$(date +%s) -lt \$END_TIME ]; do \
            echo \"Starting iperf3 client at \$(date)\"; \
            iperf3 -c \$SERVER_IP -u -b 1M -t 10 -i 1; \
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
                    echo \"Reconnected at \$(date) after \$DOWNTIME seconds of downtime\" >> /logs/downtime_log.txt; \
                    connected=true; \
                fi; \
            fi; \
            echo \"iperf3 client ended at \$(date)\"; \
            sleep 1; \
        done; \
        if [ \"\$connected\" = false ]; then \
            echo \"Client did not reconnect before the end of the test.\" >> /logs/downtime_log.txt; \
        fi"

echo "iperf3 servers and client are running."

# Allow the test to run for 30 seconds before migration
sleep 30

echo "Migrating the server from $SERVER_NAME to $IDLE_SERVER_NAME..."

# Save logs of the first server before stopping it
docker logs --timestamps $SERVER_NAME > $LOG_DIR/server_log_before_migration.txt

# Start timing of SSH setup in milliseconds
START_TIME_SSH_SETUP=$(python3 -c 'import time; print(int(time.time() * 1000))')

# Apply bandwidth limit to the first server's network interface
limit_bandwidth $SERVER_NAME eth0 $SERVER_BW_LIMIT

# Apply bandwidth limit to the second server's network interface (if needed)
limit_bandwidth $IDLE_SERVER_NAME eth0 $IDLE_SERVER_BW_LIMIT

# Copy the database file from the first server to the second server using scp
echo "Copying database file from $SERVER_NAME to $IDLE_SERVER_NAME over the network..."

# Copy SSH key from the first server to the second server to enable passwordless SSH
docker exec $SERVER_NAME ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
PUB_KEY=$(docker exec $SERVER_NAME cat /root/.ssh/id_rsa.pub)
docker exec $IDLE_SERVER_NAME mkdir -p /root/.ssh
docker exec $IDLE_SERVER_NAME sh -c "echo '$PUB_KEY' >> /root/.ssh/authorized_keys"

# Update known_hosts in the first server to avoid SSH prompts
docker exec $SERVER_NAME sh -c "ssh-keyscan -H $IDLE_SERVER_IP >> /root/.ssh/known_hosts"

# End timing of SSH setup
END_TIME_SSH_SETUP=$(python3 -c 'import time; print(int(time.time() * 1000))')

# Calculate duration of SSH setup in milliseconds
SSH_SETUP_DURATION_MS=$(($END_TIME_SSH_SETUP - $START_TIME_SSH_SETUP))

# Output the duration
echo "SSH setup duration: $SSH_SETUP_DURATION_MS milliseconds"
echo "SSH setup duration: $SSH_SETUP_DURATION_MS milliseconds" >> $LOG_DIR/timings_log.txt

# Start timing of scp command
START_TIME_SCP=$(python3 -c 'import time; print(int(time.time() * 1000))')

# Perform the scp command from the first server to the second server
docker exec $SERVER_NAME scp ./fake_database.db root@$IDLE_SERVER_IP:/app/fake_database.db

# End timing of scp command
END_TIME_SCP=$(python3 -c 'import time; print(int(time.time() * 1000))')

# Calculate duration of scp command in milliseconds
SCP_DURATION_MS=$(($END_TIME_SCP - $START_TIME_SCP))

# Output the duration
echo "SCP command duration: $SCP_DURATION_MS milliseconds"
echo "SCP command duration: $SCP_DURATION_MS milliseconds" >> $LOG_DIR/timings_log.txt

# Remove bandwidth limits
remove_bandwidth_limit $SERVER_NAME eth0
remove_bandwidth_limit $IDLE_SERVER_NAME eth0

# Stop and remove the first server container
docker stop $SERVER_NAME
docker rm $SERVER_NAME

# Stop and remove the idle server container
docker stop $IDLE_SERVER_NAME
docker rm $IDLE_SERVER_NAME

# Start the second server with the IP and MAC of the first server, mounting the same volume
docker run -d --name $IDLE_SERVER_NAME \
    --cap-add=NET_ADMIN \
    --network $NETWORK_NAME \
    --ip $SERVER_IP \
    --mac-address $SERVER_MAC \
    -v second_server_db_volume:/app \
    $CUSTOM_SERVER_IMAGE_SECOND

echo "Server migration complete."

# Allow the test to continue for the remaining time
sleep 30

# Save logs of the second server after migration
docker logs --timestamps $IDLE_SERVER_NAME > $LOG_DIR/server_log_after_migration.txt

# Save client logs
docker logs --timestamps $CLIENT_NAME > $LOG_DIR/client_log.txt

echo "Logs are stored in the '$LOG_DIR' directory."

# Clean up after the test
echo "Cleaning up containers and network..."
docker stop $CLIENT_NAME $IDLE_SERVER_NAME
docker rm $CLIENT_NAME $IDLE_SERVER_NAME
docker network rm $NETWORK_NAME
docker volume rm second_server_db_volume
