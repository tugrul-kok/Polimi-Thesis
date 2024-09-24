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

# Clean up any existing containers and network
echo "Cleaning up existing containers and network..."
docker rm -f $CLIENT_NAME $SERVER_NAME $IDLE_SERVER_NAME 2>/dev/null
docker network rm $NETWORK_NAME 2>/dev/null

# Remove old logs
rm -rf logs

# Create Docker network
docker network create --subnet=$SUBNET --gateway=$GATEWAY $NETWORK_NAME

# Create a directory for logs if it doesn't exist
mkdir -p logs

# Run active iperf3 server container (First Server)
docker run -d --name $SERVER_NAME \
    --network $NETWORK_NAME \
    --ip $SERVER_IP \
    --mac-address $SERVER_MAC \
    --entrypoint /bin/sh \
    networkstatic/iperf3 \
    -c "iperf3 -s"

# Run idle iperf3 server container (Second Server)
docker run -d --name $IDLE_SERVER_NAME \
    --network $NETWORK_NAME \
    --ip $IDLE_SERVER_IP \
    --mac-address $IDLE_SERVER_MAC \
    --entrypoint /bin/sh \
    networkstatic/iperf3 \
    -c "iperf3 -s"

# Wait a moment to ensure the servers start
sleep 2

# Run iperf3 client container with reconnect logic
docker run -d --name $CLIENT_NAME \
    --network $NETWORK_NAME \
    --ip $CLIENT_IP \
    --mac-address $CLIENT_MAC \
    -e SERVER_IP=$SERVER_IP \
    --entrypoint /bin/sh \
    networkstatic/iperf3 \
    -c "END_TIME=\$((\$(date +%s) + 120)); \
        while [ \$(date +%s) -lt \$END_TIME ]; do \
            echo \"Starting iperf3 client at \$(date)\"; \
            iperf3 -c \$SERVER_IP -u -b 1M -t 10 -i 5 --timestamps; \
            echo \"iperf3 client ended at \$(date)\"; \
            sleep 1; \
        done"

echo "iperf3 servers and client are running."

# Test connectivity from client to server
echo "Testing connectivity from client to server..."
docker exec $CLIENT_NAME ping -c 4 $SERVER_IP

# Allow the test to run for 30 seconds before migration
sleep 30

echo "Migrating the server from $SERVER_NAME to $IDLE_SERVER_NAME..."

# Save logs of the first server before stopping it
docker logs $SERVER_NAME > logs/server_log_before_migration.txt

# Stop and remove the first server container
docker stop $SERVER_NAME
docker rm $SERVER_NAME

# Stop and remove the idle server container
docker stop $IDLE_SERVER_NAME
docker rm $IDLE_SERVER_NAME

# Start the second server with the IP and MAC of the first server
docker run -d --name $IDLE_SERVER_NAME \
    --network $NETWORK_NAME \
    --ip $SERVER_IP \
    --mac-address $SERVER_MAC \
    --entrypoint /bin/sh \
    networkstatic/iperf3 \
    -c "iperf3 -s"

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
