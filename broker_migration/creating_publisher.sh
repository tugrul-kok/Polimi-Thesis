docker run -it --name mqtt-client --network mqtt_network --ip 172.18.0.20 ubuntu bash
apt-get update
apt-get install -y mosquitto-clients

mosquitto_pub -h 172.18.0.10 -t test/topic -m "Hello, MQTT"
mosquitto_sub -h 172.18.0.10 -t test/topic
