#!/bin/bash

ROOT_FOLDER="results_criu"
DAY_FOLDER=$(date +%m%d)
SIM_FOLDER=$(date +%H%M)
PUBLISHER=5
SUBSCRIBER=10

MESSAGES=10
MSG_SIZE=2048

PRETIME=2000
INTERVAL_TIME=10000
QOS=2
RETAIN="random"
#CLEANSESSION="false"
NUM_SIMULATIONS=5


echo "==================================================="
echo -ne "Cleaning the environment... "
sudo podman kill --all

echo ""
sleep 3
echo -ne "Creating folder... "
FOLDER_NAME="$ROOT_FOLDER/$DAY_FOLDER/$SIM_FOLDER"
mkdir -p $FOLDER_NAME >/dev/null 2>&1
echo "Done."

name="sim_s${MSG_SIZE}_p${PUBLISHER}_s${SUBSCRIBER}_${RETAIN}" # retain and clean session are random

echo "---------------------------------------------------"
echo "TEST: $name"
echo "PUBLISHERS: ${PUBLISHER}"
echo "SUBSCRIBERS: ${SUBSCRIBER}"
echo "MESSAGES: $MESSAGES"
echo "MESSAGES overall: $((PUBLISHER*MESSAGES-PUBLISHER*2))"
echo "MSG_SIZE: $MSG_SIZE"
echo "RETAIN $RETAIN" # CLEAN SESSION $CLEANSESSION
echo ""


echo "Creating broker..."
podman run -d --rm -p 1883:1883 --name mosquitto-broker --image-volume ignore \
        -v $(pwd)/config/mosquitto.conf:/mosquitto/config/mosquitto.conf docker.io/library/eclipse-mosquitto
        

BROKER_IP=$(podman inspect mosquitto-broker --format "{{.NetworkSettings.IPAddress}}")
echo "on IP address $BROKER_IP"

podman stats --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" mosquitto-broker |
                                     gxargs -d "\n" -L1 bash -c 'gdate "+%s%3N: $0"' |
  while IFS= read -r line
  do
    echo "$line"
  done > "$FOLDER_NAME"/"$name".txt &

echo "Logging started..."
echo ""

sleep 10

echo "Starting premigration..."
source $(pwd)/do_premigration.sh "$FOLDER_NAME" 20 &

echo "Starting publishers... "
podman run -t --rm --name bench-pub docker.io/flipperthedog/mqtt-bench mqtt-bench -action=pub \
      -broker="tcp://$BROKER_IP:1883" \
      -clients=$PUBLISHER \
      -count=$MESSAGES  \
      -size=$MSG_SIZE   \
      -qos=$QOS \
      -intervaltime=$INTERVAL_TIME -pretime=$PRETIME -x &

echo "Starting subscribers... "
podman run -t --rm --name bench-sub docker.io/flipperthedog/mqtt-bench mqtt-bench -action=sub \
      -broker="tcp://$BROKER_IP:1883" \
      -clients=$SUBSCRIBER \
      -count=$((PUBLISHER*MESSAGES-PUBLISHER*2)) \
      -qos=$QOS \
      -intervaltime=$INTERVAL_TIME -pretime=0 -x -topic="/mqtt-bench/benchmark/#"

sleep 30

pkill -P $$

echo ""
echo "Doing the final checkpoint..."
start_checkpoint=$(date -u +%s.%6N)
sudo podman container checkpoint --leave-running --tcp-established --export "$FOLDER_NAME"/final_checkpoint.tar.gz mosquitto-broker
end_checkpoint=$(date -u +%s.%6N)
elapsed_checkpoint="$(bc <<<"$end_checkpoint-$start_checkpoint")"

echo "Saving the database outside the podman container..."
start_copy=$(date +%s.%6N)
podman cp mosquitto-broker:/mosquitto/data/mosquitto.db "$FOLDER_NAME"/final_database.db
elapsed_copy="$(bc <<<"$(date -u +%s.%6N)- $start_copy")"

podman exec -t mosquitto-broker ls -lh mosquitto/data/mosquitto.db | awk '{print $5}' > "$FOLDER_NAME"/ls_"$name".txt
echo "Done."

echo "================================"
echo "TIME ELAPSED" | tee "$FOLDER_NAME"/time.txt
echo "Chekpoint: $elapsed_checkpoint s"  | tee -a "$FOLDER_NAME"/time.txt
echo "Copy: $elapsed_copy s"  | tee -a "$FOLDER_NAME"/time.txt
echo ""
echo ""
echo "Transfer state now -??-"
echo "Simulation $name done."

echo ""
echo ""

sleep 10
echo "Killing processes."
pkill -P $$
sudo podman kill --all