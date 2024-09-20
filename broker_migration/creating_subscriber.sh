docker run -it --name mqtt-subscriber --network mqtt_network --ip 172.18.0.30 ubuntu bash

apt-get update
apt-get install -y mosquitto-clients
mosquitto_sub -h 172.18.0.10 -t test/topic
