#!/bin/bash

CHECKPOINT_NAME="checkpoint-mosq"

echo "===== CRIU MIGRATION SCRIPT ====="
echo ""

echo "Starting docker..."
docker run -d --rm -p 1883:1883 --name mosquitto  \
      -v /home/antedo/migration/config/mosquitto.conf:/mosquitto/config/mosquitto.conf \
      -v /home/antedo/migration/data/:/mosquitto/data \
      eclipse-mosquitto

sleep 10

echo "Creating checkpoint..."
docker checkpoint create --leave-running --tcp-established --checkpoint-dir=/tmp/checkpoint/ mosquitto $CHECKPOINT_NAME

OUTPUT=$(docker create --rm --name mosquitto-clone \
      -v /home/antedo/migration/config/mosquitto.conf:/mosquitto/config/mosquitto.conf \
      -v /home/antedo/migration/data/:/mosquitto/data \
      eclipse-mosquitto)

echo "$OUTPUT"

echo "Moving checkpoint in the folder..."
sudo cp -r /tmp/checkpoint/$CHECKPOINT_NAME /var/lib/docker/containers/"$OUTPUT"/checkpoints/

#echo "Removing old checkpoint..."
#rm -r /tmp/checkpoint/$CHECKPOINT_NAME

echo "Starting the clone!"
docker start --checkpoint=$CHECKPOINT_NAME mosquitto-clone