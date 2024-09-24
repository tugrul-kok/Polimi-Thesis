#!/bin/bash

# Define network parameters
NETWORK_NAME=iperf-net
SUBNET=172.25.0.0/16
GATEWAY=172.25.0.1

# Define active server parameters (First Server)
SERVER_NAME=iperf-server
SERVER_IP=172.25.0.2
SERVER_MAC=02:42:ac:19:00:02

# Define client parameters
CLIENT_NAME=iperf-client
CLIENT_IP=172.25.0.3
CLIENT_MAC=02:42:ac:19:00:03

# Define idle server parameters (Second Server)
IDLE_SERVER_NAME=iperf-server2
IDLE_SERVER_IP=172.25.0.4
IDLE_SERVER_MAC=02:42:ac:19:00:04

# Custom Docker image with the fake database file
CUSTOM_SERVER_IMAGE=custom_iperf_server:latest

# Define directories for database files
DB_HOST_DIR=$(pwd)/db_files
DB_HOST_DIR_SECOND_SERVER=$(pwd)/db_files_second_server

# Define downtime log file
DOWNTIME_LOG=logs/downtime_log.txt

# Clean up any existing containers, network, and directories
echo "Cleaning up existing containers, network, and directories..."
docker rm -f $CLIENT_NAME $SERVER_NAME $IDLE_SERVER_NAME 2>/dev/null
docker network rm $NETWORK_NAME 2>/dev/null
rm -rf logs
rm -rf db_files
rm -rf db_files_second_server

# Build custom Docker image for the server with the fake database
echo "Building custom Docker image with the fake database..."
docker build -t $CUSTOM_SERVER_IMAGE ./iperf_server_with_db

# Create directories for database files
mkdir -p $DB_HOST_DIR
mkdir -p $DB_HOST_DIR_SECOND_SERVER

# Create Docker network
docker network create --subnet=$SUBNET --gateway=$GATEWAY $NETWORK_NAME

# Create a directory for logs
mkdir -p logs

# Run active iperf3 server container (First Server) with fake database
docker run -d --name $SERVER_NAME \
    --network $NETWORK_NAME \
    --ip $SERVER_IP \
    --mac-address $SERVER_MAC \
    $CUSTOM_SERVER_IMAGE

# Run idle iperf3 server container (Second Server) without the database
docker run -d --name $IDLE_SERVER_NAME \
    --network $NETWORK_NAME \
    --ip $IDLE_SERVER_IP \
    --mac-address $IDLE_SERVER_MAC \
    networkstatic/iperf3 \
    iperf3 -s

# Wait a moment to ensure the servers start
sleep 2

# Run iperf3 client container with reconnect logic and downtime measurement
docker run -d --name $CLIENT_NAME \
    --network $NETWORK_NAME \
    --ip $CLIENT_IP \
    --mac-address $CLIENT_MAC \
    -e SERVER_IP=$SERVER_IP \
    -v $(pwd)/logs:/logs \
    --entrypoint /bin/sh \
    networkstatic/iperf3 \
    -c "END_TIME=\$((\$(date +%s) + 120)); \
        connected=true; \
        while [ \$(date +%s) -lt \$END_TIME ]; do \
            echo \"Starting iperf3 client at \$(date)\"; \
            iperf3 -c \$SERVER_IP -u -b 1M -t 10 -i 5 --timestamps; \
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

# Copy the database file from the first server container to the host
docker cp $SERVER_NAME:/app/fake_database.db $DB_HOST_DIR/fake_database.db

# Stop and remove the first server container
docker stop $SERVER_NAME
docker rm $SERVER_NAME

# Stop and remove the idle server container
docker stop $IDLE_SERVER_NAME
docker rm $IDLE_SERVER_NAME

# Copy the database file to the second server's directory
cp $DB_HOST_DIR/fake_database.db $DB_HOST_DIR_SECOND_SERVER/

# Start the second server with the IP and MAC of the first server, with its own database volume
docker run -d --name $IDLE_SERVER_NAME \
    --network $NETWORK_NAME \
    --ip $SERVER_IP \
    --mac-address $SERVER_MAC \
    -v $DB_HOST_DIR_SECOND_SERVER:/app \
    $CUSTOM_SERVER_IMAGE

echo "Server migration complete."

# Allow the test to continue for the remaining time
sleep 95

# Save logs of the second server after migration
docker logs $IDLE_SERVER_NAME > logs/server_log_after_migration.txt

# Save client logs
docker logs $CLIENT_NAME > logs/client_log.txt

echo "Logs are stored in the 'logs' directory."

# Clean up after the test
echo "Cleaning up containers and network..."
docker stop $CLIENT_NAME $IDLE_SERVER_NAME
docker rm $CLIENT_NAME $IDLE_SERVER_NAME
docker network rm $NETWORK_NAME
