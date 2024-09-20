### Creating Network

docker network rm mqtt_network
docker network create --subnet=172.18.0.0/16 mqtt_network

### Creating Broker
docker rm -f emqx-broker
docker run -d --name emqx-broker --network mqtt_network --ip 172.18.0.10 -p 1883:1883 -p 8083:8083 -p 18083:18083 emqx/emqx

# ##Creating Publisher
docker run -it --name mqtt-client --network mqtt_network --ip 172.18.0.20 ubuntu bash

Inside the container:
docker exec -it mqtt-publisher bash
apt-get update
apt-get install -y python3 python3-pip
apt-get install python3-paho-mqtt
apt-get install -y iperf3

nano publish_periodic.py

import paho.mqtt.client as mqtt
import time

# MQTT Settings
broker = "172.18.0.10"
port = 1883
topic = "test/topic"

# Create an MQTT client instance
client = mqtt.Client()

# Connect to the broker
client.connect(broker, port, 60)

# Start a loop to publish messages periodically
try:
    while True:
        message = f"Hello from Publisher at {time.ctime()}"
        client.publish(topic, message)
        print(f"Published: {message}")
        time.sleep(5)  # Publish every 5 seconds
except KeyboardInterrupt:
    print("Publishing stopped.")

# Disconnect from the broker
client.disconnect()

python3 publish_periodic.py

### For subscriber:

docker run -it --name mqtt-subscriber --network mqtt_network --ip 172.18.0.30 ubuntu bash
apt-get update
apt-get install -y mosquitto-clients

docker exec -it mqtt-subscriber bash
mosquitto_sub -h 172.18.0.10 -t test/topic

### To listen

### Copying files
docker run -d --name new-mqtt-container --network mqtt_network --ip 172.18.0.10 \
  -v /Users/tugrul/Desktop/Tez/mqtt_migration/broker_backup/emqx:/opt/emqx \
  -p 1883:1883 -p 8083:8083 -p 18083:18083 \
  ubuntu /opt/emqx/bin/emqx start

docker exec -it --user root emqx-broker bash
tar -czvf /opt/emqx-backup.tar.gz /opt/emqx
docker cp emqx-broker:/opt/emqx-backup.tar.gz /Users/tugrul/Desktop/Tez/mqtt_migration/broker_backup/emqx/

docker cp /Users/tugrul/Desktop/Tez/mqtt_migration/broker_backup/emqx-backup.tar.gz new-emqx-broker:/opt/
docker exec -it new-emqx-broker bash
tar -xzvf /opt/emqx-backup.tar.gz -C /opt/
/opt/emqx/bin/emqx start
