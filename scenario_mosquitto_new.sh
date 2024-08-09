#!/bin/bash

ROUND=1
PUBLISHER=(1 1 1) #1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 3 3 3 3 3 3 3 3 3 3 4 4 4 4 4 4 4 4 4 4 5 5 5 5 5 5 5 5 5 5 6 6 6 6 6 6 6 6 6 6 7 7 7 7 7 7 7 7 7 7 8 8 8 8 8 8 8 8 8 8 16 16 16 16 16 16 16 16 16 16 32 32 32 32 32 32 32 32 32 32)
SUBSCRIBER=(1 2 3) #4 5 6 7 8 16 32 1 2 3 4 5 6 7 8 16 32 1 2 3 4 5 6 7 8 16 32 1 2 3 4 5 6 7 8 16 32 1 2 3 4 5 6 7 8 16 32 1 2 3 4 5 6 7 8 16 32 1 2 3 4 5 6 7 8 16 32 1 2 3 4 5 6 7 8 16 32 1 2 3 4 5 6 7 8 16 32 1 2 3 4 5 6 7 8 16 32)
MESSAGES=20
MSG_SIZE=(1024 2048 4096 8192 16384) #1024 2048 4096 8192 16384)
PRETIME=2000
INTERVAL_TIME=10000
RETAIN_VALUES=("true" "false")
QOS_VALUES=(0 1 2)
TOPIC_NUMBERS=(1 4 8)
RESULTS_FOLDER_BASE="results_new/"

BROKER="tcp://172.20.0.2:1883"

mkdir -p $RESULTS_FOLDER_BASE

echo "Creating a new network..."
docker network rm myNet

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

            echo "==================================================="
            echo "Cleaning the environment..."
            docker stop $(docker ps -a -q)
            docker rm $(docker ps -a -q)

            echo ""
            sleep 1
            docker login
            name="sim${round}_s${size}_p${PUBLISHER[i]}_s${SUBSCRIBER[i]}_${retain}_qos${qos}_topics${topics}"
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
            echo ""

            echo "Creating broker..."
            docker run -d --rm --name mosquitto-broker --network myNet -v $PWD/config/mosquitto.conf:/mosquitto/config/mosquitto.conf eclipse-mosquitto
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
              docker run -t --rm --name bench-pub-${t} --network myNet flipperthedog/mqtt-bench mqtt-bench -action=pub -broker=$BROKER \
                    -clients="${PUBLISHER[i]}" \
                    -count=$MESSAGES  \
                    -size="$size"   \
                    -qos=$qos \
                    -retain=$retain \
                    -intervaltime=$INTERVAL_TIME -pretime=$PRETIME -topic="/mqtt-bench/benchmark/topic_${t}" -x &
            done

            echo "Starting subscriber"
            docker run -t --rm --name bench-sub --network myNet flipperthedog/mqtt-bench mqtt-bench -action=sub -broker=$BROKER \
                  -clients="${SUBSCRIBER[i]}" \
                  -count=$((PUBLISHER[i]*MESSAGES-PUBLISHER[i]*2)) \
                  -qos=$qos \
                  -intervaltime=$INTERVAL_TIME -pretime=0 -x -topic="/mqtt-bench/benchmark/#"

            echo ""

            sleep 30
            docker exec -t mosquitto-broker ls -lh mosquitto/data/mosquitto.db | awk '{print $5}' > $RESULTS_FOLDER/ls_"$name".txt &
            echo "Simulation $name done."
            sleep 3
            echo ""
            echo ""

          done
        done
      done
    done
  done
  sleep 5
done

sleep 10
echo "Killing processes."
pkill -P $$
