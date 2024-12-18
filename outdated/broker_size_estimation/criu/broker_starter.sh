BROKER="tcp://172.20.0.2:1883"

echo "Creating a new network..."
docker network rm myNet

docker network create \
		--driver=bridge \
		--subnet=172.20.0.0/16 \
		--ip-range=172.20.0.0/24 \
		myNet

docker run -d --rm --name mosquitto-broker --network myNet -v $(pwd)/config/mosquitto.conf:/mosquitto/config/mosquitto.conf eclipse-mosquitto


#docker run -d --name mosquitto-broker -p 1883:1883 -v $(pwd)/config/mosquitto.conf:/mosquitto/config/mosquitto.conf -v $(pwd)/config/mosquitto/data:/mosquitto/data -v $(pwd)/config/mosquitto/log:/mosquitto/log eclipse-mosquitto 