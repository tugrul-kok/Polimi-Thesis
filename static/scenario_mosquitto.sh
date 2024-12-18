#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --ROUND <number>"
    echo "  --PUBLISHER <comma-separated values>"
    echo "  --SUBSCRIBER <comma-separated values>"
    echo "  --MESSAGES_NUM <number>"
    echo "  --MSG_SIZE <number>"
    echo "  --PRETIME <number>"
    echo "  --INTERVAL_TIME <number>"
    echo "  --RETAIN_VALUES <comma-separated true/false>"
    echo "  --QOS_VALUES <comma-separated values>"
    echo "  --TOPIC_NUMBERS <comma-separated values>"
    echo "  --CLEAN_SESSION <comma-separated true/false>"
    echo "  --RESULTS_FOLDER_BASE <path>"
    echo "  -h | --help"
    exit 1
}

# Initialize variables with default values if needed
ROUND=1
PUBLISHER=(1)
SUBSCRIBER=(3)
MESSAGES_NUM=20
MSG_SIZE=1024
PRETIME=1000
INTERVAL_TIME=1000
RETAIN_VALUES=(false)
QOS_VALUES=(0 1 2)
TOPIC_NUMBERS=(1)
CLEAN_SESSION=(true)
RESULTS_FOLDER_BASE="results"

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ROUND) ROUND="$2"; shift ;;
        --PUBLISHER) IFS=',' read -r -a PUBLISHER <<< "$2"; shift ;;
        --SUBSCRIBER) IFS=',' read -r -a SUBSCRIBER <<< "$2"; shift ;;
        --MESSAGES_NUM) MESSAGES_NUM="$2"; shift ;;
        --MSG_SIZE) IFS=',' read -r -a MSG_SIZE <<< "$2"; shift ;;
        --PRETIME) PRETIME="$2"; shift ;;
        --INTERVAL_TIME) INTERVAL_TIME="$2"; shift ;;
        --RETAIN_VALUES) IFS=',' read -r -a RETAIN_VALUES <<< "$2"; shift ;;
        --QOS_VALUES) IFS=',' read -r -a QOS_VALUES <<< "$2"; shift ;;
        --TOPIC_NUMBERS) IFS=',' read -r -a TOPIC_NUMBERS <<< "$2"; shift ;;
        --CLEAN_SESSION) IFS=',' read -r -a CLEAN_SESSION <<< "$2"; shift ;;
        --RESULTS_FOLDER_BASE) RESULTS_FOLDER_BASE="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Example of using the variables
echo "ROUND: $ROUND"
echo "PUBLISHER: ${PUBLISHER[@]}"
echo "SUBSCRIBER: ${SUBSCRIBER[@]}"
echo "MESSAGES_NUM: $MESSAGES_NUM"
echo "MSG_SIZE: ${MSG_SIZE[@]}"
echo "PRETIME: $PRETIME"
echo "INTERVAL_TIME: $INTERVAL_TIME"
echo "RETAIN_VALUES: ${RETAIN_VALUES[@]}"
echo "QOS_VALUES: ${QOS_VALUES[@]}"
echo "TOPIC_NUMBERS: ${TOPIC_NUMBERS[@]}"
echo "CLEAN_SESSION: ${CLEAN_SESSION[@]}"
echo "RESULTS_FOLDER_BASE: $RESULTS_FOLDER_BASE"

# Here you can add the command to run your simulation using the above variables
# For example:
# ./simulation_executable --round "$ROUND" --publisher "${PUBLISHER[@]}" ... etc.

BROKER="tcp://172.20.0.2:1883"

# Path to mosquitto_db_dump utility
MOSQUITTO_DB_DUMP="$PWD/db_dump/mosquitto_db_dump"

mkdir -p $RESULTS_FOLDER_BASE

# Define the logging function
function log_mosquitto_db() {
  local timestamp=$(gdate "+%s%3N")
  if docker exec mosquitto-broker test -f /mosquitto/data/mosquitto.db; then
    echo "Copying mosquitto.db from container to host..."
    docker cp mosquitto-broker:/mosquitto/data/mosquitto.db $RESULTS_FOLDER/mosquitto_${name}_${timestamp}.db

    echo "Running mosquitto_db_dump..."
    $MOSQUITTO_DB_DUMP $RESULTS_FOLDER/mosquitto_${name}_${timestamp}.db > $RESULTS_FOLDER/mosquitto_db_dump_${name}_${timestamp}.txt

    ls -lh $RESULTS_FOLDER/mosquitto_${name}_${timestamp}.db | awk '{print $5}' > $RESULTS_FOLDER/ls_${name}_${timestamp}.txt
  else
    echo "mosquitto.db does not exist yet."
  fi
}


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
    for retain in "${RETAIN_VALUES[@]}"; do
      for clean in "${CLEAN_SESSION[@]}"; do
        for size in "${MSG_SIZE[@]}"; do
          for qos in "${QOS_VALUES[@]}"; do
            for topics in "${TOPIC_NUMBERS[@]}"; do
              for MESSAGES in "${MESSAGES_NUM[@]}"; do

                # Skip cases when retain is false and clean is true
                #if [[ "$retain" == "false" && "$clean" == "true" ]]; then
                #  continue
                #fi

                name="sim${round}_p${PUBLISHER[i]}_s${SUBSCRIBER[i]}_retain_${retain}__clean_${clean}_s${size}_qos${qos}_topics${topics}_messagenum_${MESSAGES}"
                RESULTS_FOLDER="$RESULTS_FOLDER_BASE/p${PUBLISHER[i]}_s${SUBSCRIBER[i]}/retain_${retain}_clean_${clean}/s${size}/qos_${qos}_topics_${topics}"

                # Add this conditional check
                if [ -d "$RESULTS_FOLDER" ]; then
                    echo "Results folder $RESULTS_FOLDER already exists. Skipping simulation."
                    continue
                fi

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
                docker run -d --rm --name mosquitto-broker --network myNet -v $PWD/mosquitto/config/mosquitto.conf:/mosquitto/config/mosquitto.conf eclipse-mosquitto:1.6.9
                echo ""

                docker stats --format "{{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" mosquitto-broker |
                  gxargs -d "\n" -L1 bash -c 'gdate "+%s%3N: $0"' |
                  while IFS= read -r line; do
                    echo "$line"
                  done > $RESULTS_FOLDER/"$name".txt &

                echo "Logging started..."
                echo ""

                echo "Starting publisher"
                for ((t=1; t<=topics; t++)); do
                  docker run -t --rm --name bench-pub-${t} --network myNet mqtt-bench -action=pub -broker=$BROKER \
                        -clients="${PUBLISHER[i]}" \
                        -count=$MESSAGES   \
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
                      -intervaltime=$INTERVAL_TIME -pretime=0 -x -topic="/mqtt-bench/benchmark/#" &
                SUBSCRIBER_PID=$!

                # Start logging in the background
                (
                  while kill -0 $SUBSCRIBER_PID 2>/dev/null; do
                    log_mosquitto_db
                    sleep $(($INTERVAL_TIME / 1000)).$(($INTERVAL_TIME % 1000))
                  done
                ) &
                LOGGER_PID=$!

                # Wait for the subscriber to finish
                wait $SUBSCRIBER_PID

                # Wait for the logging process to finish
                wait $LOGGER_PID

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
