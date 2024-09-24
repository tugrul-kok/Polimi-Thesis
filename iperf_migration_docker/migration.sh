#!/bin/bash

# Names for the network and containers
network_name="iperf_network"
server_container="iperf_server"
client_container="iperf_client"
second_server_container="iperf_server2"  # Name for the second iPerf server

# Clean up existing containers and network
rm *txt
docker rm -f $server_container $client_container $second_server_container
docker network rm $network_name

# Create a new network with a specified subnet
docker network create --subnet=192.168.100.0/24 $network_name

# Create and start the iPerf server container
docker run -d \
  --name $server_container \
  --network $network_name \
  --ip 192.168.100.2 \
  --mac-address "02:42:c0:a8:64:02" \
  networkstatic/iperf3 -s

# Wait a bit for the server to start
sleep 5

# Create and start the iPerf client container to send UDP packets
docker run -d \
  --name $client_container \
  --network $network_name \
  --ip 192.168.100.3 \
  --mac-address "02:42:c0:a8:64:03" \
  networkstatic/iperf3 -c 192.168.100.2 -u -b 100M -t 10

echo "Setup complete. iPerf server and client are ready."
echo "Fetching logs from iPerf server and client..."

sleep 10

# Start a second iPerf server on a different IP
echo "Starting second iPerf server..."
docker run -d \
  --name $second_server_container \
  --network $network_name \
  --ip 192.168.100.4 \
  --mac-address "02:42:c0:a8:64:04" \
  networkstatic/iperf3 -s

echo "Second iPerf server is running."

# Fetch logs from the iPerf server
echo "Logs from iPerf server:"
docker logs $server_container > server_logs.txt

# Fetch logs from the iPerf client
echo "Logs from iPerf client:"
docker logs $client_container > client_logs.txt

echo "Logs from second iPerf server:"
docker logs $second_server_container > second_server_container.txt
