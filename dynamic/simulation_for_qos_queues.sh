#!/bin/bash

# Set simulation parameters
ROUND=(1)
PUBLISHERS=(1)
SUBSCRIBER=(1)
MESSAGES_NUM=20
MSG_SIZE=1024
PRETIME=1000
INTERVAL_TIME=1000
RETAIN_VALUES=(false true)
CLEAN_SESSION=(true) # Set to true to indicate a clean session
QOS_VALUES=(1 2) # Using QoS 1 and 2 for guaranteed delivery with ACK
TOPIC_NUMBERS=(1)

RESULTS_FOLDER_BASE="results_qos"

BROKER="tcp://172.20.0.2:1883"

# Path to mosquitto_db_dump utility
MOSQUITTO_DB_DUMP=" $PWD/mosquitto_db_dump"

mkdir -p $RESULTS_FOLDER_BASE

# Define the logging function
function log_mosquitto_db() {
  local timestamp=$(gdate "+%s%3N")
  if docker exec mosquitto-broker test -f /mosquitto/data/mosquitto.db; then
    echo "Copying mosquitto.db from container to host..."
    docker cp mosquitto-broker:/mosquitto/data/mosquitto.db $RESULTS_FOLDER/mosquitto_${name}_${timestamp}.db

    echo "Running mosquitto_db_dump..."
    $MOSQUITTO_DB_DUMP $RESULTS_FOLDER/mosquitto_${name}_${timestamp}.db > $RESULTS_FOLDER/mosquitto_db_dump_${name}_${timestamp}.txt

    local db_size=$(ls -lh $RESULTS_FOLDER/mosquitto_${name}_${timestamp}.db | sed 's/,/./g' | awk '{print $5}')
    echo $db_size > $RESULTS_FOLDER/ls_${name}_${timestamp}.txt
    echo "$timestamp,$db_size" >> $CSV_FILE
  else
    echo "mosquitto.db does not exist yet."
  fi
}

# Loop through each round
for round in "${ROUND[@]}"; do
  for retain in "${RETAIN_VALUES[@]}"; do
    for clean in "${CLEAN_SESSION[@]}"; do
      for qos in "${QOS_VALUES[@]}"; do
        for topic_num in "${TOPIC_NUMBERS[@]}"; do

          # Clean up previous containers and network
          docker stop mosquitto-broker &>/dev/null
          docker rm mosquitto-broker &>/dev/null
          docker rm -f $(docker ps -aq --filter "name=bench-") &>/dev/null

          if docker network inspect myNet &>/dev/null; then
            docker network rm myNet &>/dev/null
          fi

          echo "Creating a new network..."
          docker network create \
              --driver=bridge \
              --subnet=172.20.0.0/16 \
              --ip-range=172.20.0.0/24 \
              myNet

          name="sim_p${PUBLISHERS[0]}_s${SUBSCRIBER[0]}_retain_${retain}_clean_${clean}_s${MSG_SIZE}_qos${qos}_round_${round}"
          RESULTS_FOLDER="$RESULTS_FOLDER_BASE/round_${round}/retain_${retain}_clean_${clean}/qos_${qos}"
          CSV_FILE="$RESULTS_FOLDER_BASE/round_${round}_p_${PUBLISHERS[0]}_s_${SUBSCRIBER[0]}_m_${MSG_SIZE}_r_${retain}_c_${clean}_qos_${qos}_t_${topic_num}.csv"
          mkdir -p $RESULTS_FOLDER
          touch $CSV_FILE

          # Start broker
          docker run -d --rm --name mosquitto-broker --network myNet -v $PWD/config/mosquitto.conf:/mosquitto/config/mosquitto.conf eclipse-mosquitto:1.6.9 &>/dev/null

          # Set total simulation time and start logger
          TOTAL_SIMULATION_TIME=60 # Adjust as needed
          END_TIME=$((SECONDS + TOTAL_SIMULATION_TIME))
          (
            while [ $SECONDS -lt $END_TIME ]; do
                log_mosquitto_db
                sleep $(($INTERVAL_TIME / 10000)).$(($INTERVAL_TIME % 10000))
            done
          ) &
          LOGGER_PID=$!

          # Start publishers in the background
          for ((p=1; p<=PUBLISHERS[0]; p++)); do
              docker run -d --rm --name bench-pub-$p --network myNet mqtt-bench -action=pub -broker=$BROKER \
                  -clients=1 \
                  -count=$((MESSAGES_NUM * 2)) \
                  -size="$MSG_SIZE" \
                  -qos=$qos \
                  -retain=$retain \
                  -clean-session=$clean \
                  -intervaltime=$INTERVAL_TIME -pretime=$PRETIME -topic="/mqtt-bench/benchmark/topic_$p" &>/dev/null
          done

          PUBLISHER_CONTAINER_IDS=$(docker ps -qf "name=bench-pub-")

          # Start subscribers in the background
          for ((s=1; s<=SUBSCRIBER[0]; s++)); do
              docker run -d --rm --name bench-sub-$s --network myNet mqtt-bench -action=sub -broker=$BROKER \
                  -clients=1 \
                  -count=$((MESSAGES_NUM * 2)) \
                  -qos=$qos \
                  -retain=$retain \
                  -clean-session=$clean \
                  -intervaltime=$INTERVAL_TIME -pretime=0 -x -topic="/mqtt-bench/benchmark/#" &>/dev/null
          done

          SUBSCRIBER_CONTAINER_IDS=$(docker ps -qf "name=bench-sub-")

          # Wait for some time to allow messages to be published and start being delivered
          sleep 5

          # Disconnect all subscribers from the network before they have acknowledged all messages
          for ((s=1; s<=SUBSCRIBER[0]; s++)); do
              SUBSCRIBER_TO_DISCONNECT="bench-sub-$s"
              docker network disconnect myNet $SUBSCRIBER_TO_DISCONNECT &>/dev/null
              local timestamp=$(gdate "+%s%3N")
              echo "$timestamp,dis" >> $CSV_FILE
              echo "Subscriber $SUBSCRIBER_TO_DISCONNECT disconnected from the network forcefully before acknowledging all messages."
          done

          # Allow publishers to continue sending messages
          sleep 10

          # Reconnect all subscribers to the network to receive undelivered messages
          for ((s=1; s<=SUBSCRIBER[0]; s++)); do
              SUBSCRIBER_TO_RECONNECT="bench-sub-$s"
              docker network connect myNet $SUBSCRIBER_TO_RECONNECT &>/dev/null
              local timestamp=$(gdate "+%s%3N")
              echo "$timestamp,rec" >> $CSV_FILE
              echo "Subscriber $SUBSCRIBER_TO_RECONNECT reconnected to the network to receive undelivered messages."
          done

          # Wait for the simulation to complete
          sleep 20

          # Clean up
          docker stop mosquitto-broker &>/dev/null
          docker rm -f $(docker ps -aq --filter "name=bench-") &>/dev/null

          # Remove network
          docker network rm myNet &>/dev/null

          # Stop the logger
          kill $LOGGER_PID



        done
      done
    done
  done
done
