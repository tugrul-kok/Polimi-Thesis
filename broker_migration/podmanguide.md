podman network create --subnet 192.168.100.0/24 mqtt-net

podman run -d --name mosquitto-broker --network mqtt-net --ip 192.168.100.10 --mac-address 02:42:ac:11:00:02 -p 1883:1883 eclipse-mosquitto

podman run -d --name mqtt-publisher --network mqtt-net --ip 192.168.100.11 --mac-address 02:42:ac:11:00:03 python:3.9-slim sleep infinity

podman run -d --name mqtt-subscriber --network mqtt-net --ip 192.168.100.12 --mac-address 02:42:ac:11:00:04 python:3.9-slim sleep infinity

podman exec -it mqtt-subscriber pip install paho-mqtt
