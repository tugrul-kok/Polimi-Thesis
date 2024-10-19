#!/bin/bash

ROUND=1
PUBLISHER=(1)
SUBSCRIBER=(1)
MESSAGES_NUM=(10 20 30 40 50)
MSG_SIZE=(1024) #1024 2048 4096 8192 16384)
PRETIME=2000
INTERVAL_TIME=10000
RETAIN_VALUES=(true)
QOS_VALUES=(0)
TOPIC_NUMBERS=(1)
CLEAN_SESSION=(true)
RESULTS_FOLDER_BASE="results_tests/"

BROKER="tcp://172.20.0.2:1883"

# Path to mosquitto_db_dump utility
MOSQUITTO_DB_DUMP="/Users/tugrul/Desktop/Tez/mqtt_broker_size_estimation/my_migration/mosquitto/apps/db_dump/mosquitto_db_dump"

mkdir -p $RESULTS_FOLDER_BASE

echo "Creating a new network..."
if docker network inspect myNet &>/dev/null; then
  docker network rm myNet
fi

docker network create \
    --driver=bridge \
    --subnet=172.20.0.0/16 \
    --ip-range=172.20.0.0/24 \
    myNet

echo 3

for ((round=0; round<ROUND; round++)); do
  for i in "${!PUBLISHER[@]}"; do
    for size in "${MSG_SIZE[@]}"; do
      for retain in "${RETAIN_VALUES[@]}"; do
        for qos in "${QOS_VALUES[@]}"; do
          for topics in "${TOPIC_NUMBERS[@]}"; do
            for MESSAGES in "${MESSAGES_NUM[@]}"; do
              for clean in "${CLEAN_SESSION[@]}"; do
                echo "==================================================="
                echo "Cleaning the environment..."

                containers=$(docker ps -a -q)
                if [ -n "$containers" ]; then
                  docker stop $containers
                  docker rm $containers
                else
                  echo "No containers to stop or remove."
                fi

                echo ""
                sleep 1
                docker login
                name="sim${round}_s${size}_p${PUBLISHER[i]}_s${SUBSCRIBER[i]}_${retain}_qos${qos}_topics${topics}_messagenum_${MESSAGES}"
                RESULTS_FOLDER="$RESULTS_FOLDER_BASE/p${PUBLISHER[i]}_s${SUBSCRIBER[i]}"
                mkdir -p $RESULTS_FOLDER
                echo "---------------------------------------------------"
                echo "TEST: $name"
                echo "ROUND: $round"
                echo "PUBLISHERS: ${PUBLISHER[i]}"
                echo "SUBSCRIBERS: ${SUBSCRIBER[i]}"
                echo "MESSAGES: $MESSAGES"
                echo "MSG_SIZE: $size"
                echo "RETAIN: $retain"
                echo "QoS: $qos"
                echo "TOPICS: $topics"
                echo "CLEAN SESSION: $clean"
                echo ""

                echo "Creating broker..."
                docker run -d --rm --name mosquitto-broker --network myNet -v $PWD/config/mosquitto.conf:/mosquitto/config/mosquitto.conf eclipse-mosquitto:1.6.9
                echo ""

                docker stats --format "{{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" mosquitto-broker |
                  gxargs -d "\n" -L1 bash -c 'gdate "+%s%3N: $0"' |
                  while IFS= read -r line; do
                    echo "$line"
                  done > $RESULTS_FOLDER/"$name".txt &

                echo "Logging started..."
                echo ""

                sleep 10
                echo "Starting publisher"
                for ((t=1; t<=topics; t++)); do
                  docker run -t --rm --name bench-pub-${t} --network myNet mqtt-bench -action=pub -broker=$BROKER \
                        -clients="${PUBLISHER[i]}" \
                        -count=$MESSAGES  \
                        -size="$size"   \
                        -qos=$qos \
                        -retain=$retain \
                        -clean-session=$clean \
                        -intervaltime=$INTERVAL_TIME -pretime=$PRETIME -topic="/mqtt-bench/benchmark/topic_${t}" -x &
                done

                echo "Starting subscriber"
                docker run -t --rm --name bench-sub --network myNet mqtt-bench -action=sub -broker=$BROKER \
                      -clients="${SUBSCRIBER[i]}" \
                      -count=$(( PUBLISHER[i] * topics * MESSAGES )) \
                      -qos=$qos \
                      -retain=$retain \
                      -clean-session=$clean \
                      -intervaltime=$INTERVAL_TIME -pretime=0 -x -topic="/mqtt-bench/benchmark/#"

                echo ""

                sleep 30

                # Copy mosquitto.db from the container to the host and rename it
                echo "Copying mosquitto.db from container to host..."
                docker cp mosquitto-broker:/mosquitto/data/mosquitto.db $RESULTS_FOLDER/mosquitto_$name.db

                # Run mosquitto_db_dump on the copied database file
                echo "Running mosquitto_db_dump..."
                $MOSQUITTO_DB_DUMP $RESULTS_FOLDER/mosquitto_$name.db > $RESULTS_FOLDER/mosquitto_db_dump_$name.txt

                # Optionally, get the size of the mosquitto.db file and save it
                ls -lh $RESULTS_FOLDER/mosquitto_$name.db | awk '{print $5}' > $RESULTS_FOLDER/ls_"$name".txt &

                echo "Simulation $name done."
                sleep 3
                echo ""
                echo ""
              done
            done
          done
        done
      done
    done
    sleep 5
  done
done

sleep 10
echo "Killing processes."
pkill -P $$
