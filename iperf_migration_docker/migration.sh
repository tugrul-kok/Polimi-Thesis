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

# Custom Docker images
CUSTOM_SERVER_IMAGE_FIRST=custom_iperf_server_first
CUSTOM_SERVER_IMAGE_SECOND=custom_iperf_server_second
CUSTOM_CLIENT_IMAGE=custom_iperf_client

# Define downtime log file
DOWNTIME_LOG=logs/downtime_log.txt

# Clean up any existing containers, networks, volumes, and directories
echo "Cleaning up existing containers, networks, volumes, and directories..."
docker rm -f $CLIENT_NAME $SERVER_NAME $IDLE_SERVER_NAME 2>/dev/null
docker network rm $NETWORK_NAME 2>/dev/null
docker volume rm second_server_db_volume 2>/dev/null
rm -rf logs

# Create Docker network
docker network create --subnet=$SUBNET --gateway=$GATEWAY $NETWORK_NAME

# Create a directory for logs
mkdir -p logs

# Build custom Docker images
echo "Building custom Docker images..."
docker build -t $CUSTOM_SERVER_IMAGE_FIRST -f Dockerfile.first .
docker build -t $CUSTOM_SERVER_IMAGE_SECOND -f Dockerfile.second .
docker build -t $CUSTOM_CLIENT_IMAGE -f Dockerfile.client .

# Create a Docker volume for the second server's database
docker volume create second_server_db_volume

# Run active iperf3 server container (First Server)
docker run -d --name $SERVER_NAME \
    --network $NETWORK_NAME \
    --ip $SERVER_IP \
    --mac-address $SERVER_MAC \
    $CUSTOM_SERVER_IMAGE_FIRST

# Run idle iperf3 server container (Second Server) with the database volume
docker run -d --name $IDLE_SERVER_NAME \
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
    -v $(pwd)/logs:/logs \
    $CUSTOM_CLIENT_IMAGE \
    -c "END_TIME=\$((\$(date +%s) + 120)); \
        connected=true; \
        while [ \$(date +%s) -lt \$END_TIME ]; do \
            echo \"Starting iperf3 client at \$(date)\"; \
            iperf3 -c \$SERVER_IP -u -b 1M -t 10 -i 5; \
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
docker logs $SERVER_NAME > logs/server_log_before_migration.txt

# Copy the database file from the first server to the second server using scp
echo "Copying database file from $SERVER_NAME to $IDLE_SERVER_NAME over the network..."

# Copy SSH key from the first server to the second server to enable passwordless SSH
docker exec $SERVER_NAME ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
PUB_KEY=$(docker exec $SERVER_NAME cat /root/.ssh/id_rsa.pub)
docker exec $IDLE_SERVER_NAME mkdir -p /root/.ssh
docker exec $IDLE_SERVER_NAME sh -c "echo '$PUB_KEY' >> /root/.ssh/authorized_keys"

# Update known_hosts in the first server to avoid SSH prompts
docker exec $SERVER_NAME sh -c "ssh-keyscan -H $IDLE_SERVER_IP >> /root/.ssh/known_hosts"

# Perform the scp command from the first server to the second server
docker exec $SERVER_NAME scp ./fake_database.db root@$IDLE_SERVER_IP:/app/fake_database.db

# Stop and remove the first server container
docker stop $SERVER_NAME
docker rm $SERVER_NAME

# Stop and remove the idle server container
docker stop $IDLE_SERVER_NAME
docker rm $IDLE_SERVER_NAME

# Start the second server with the IP and MAC of the first server, mounting the same volume
docker run -d --name $IDLE_SERVER_NAME \
    --network $NETWORK_NAME \
    --ip $SERVER_IP \
    --mac-address $SERVER_MAC \
    -v second_server_db_volume:/app \
    $CUSTOM_SERVER_IMAGE_SECOND

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
docker volume rm second_server_db_volume
