#!/bin/bash

ROUND=1
# PUBLISHER=( 1 10 50 100 )
# SUBSCRIBER=( 5 15 75 150 )

PUBLISHER=( 50 )
SUBSCRIBER=( 75 )

MESSAGES=20
#MSG_SIZE=( 2048 5120 10240 52100 102400 )
MSG_SIZE=( 1024 2048 4096 8192 16384 )
PRETIME=2000
INTERVAL_TIME=10000
QOS=2
RETAIN="random"
#CLEANSESSION="false"
NUM_SIMULATIONS=1

BROKER="tcp://172.20.0.2:1883"

echo "Creating a new network..."
docker network rm myNet

docker network create \
		--driver=bridge \
		--subnet=172.20.0.0/16 \
		--ip-range=172.20.0.0/24 \
		myNet

echo 3

for ((round=0; i<ROUND; round++));
do
  for i in "${!PUBLISHER[@]}";
#  for client in "${CLIENTS[@]}"
  do
    for size in "${MSG_SIZE[@]}"
    do
      echo "==================================================="
      echo "Cleaning the environment..."
      docker stop $(docker ps -a -q)
      docker rm $(docker ps -a -q)

      echo ""
      sleep 1
      docker login
#      name="sim${round}_s${size}_c${client}_r${RETAIN}_s${CLEANSESSION}"
      name="sim${round}_s${size}_p${PUBLISHER[i]}_s${SUBSCRIBER[i]}_${RETAIN}" # retain and clean session are random

      echo "---------------------------------------------------"
      echo "TEST: $name"
      echo "ROUND: $round"
#      echo "CLIENTS: $client"
      echo "PUBLISHERS: ${PUBLISHER[i]}"
      echo "SUBSCRIBERS: ${SUBSCRIBER[i]}"
      echo "MESSAGES: $MESSAGES"
      echo "MESSAGES overall: $((PUBLISHER[i]*MESSAGES-PUBLISHER[i]*2))"
      echo "MSG_SIZE: $size"
      echo "RETAIN $RETAIN" # CLEAN SESSION $CLEANSESSION
      echo ""


      echo "Creating broker..."
      docker run -d --rm --name mosquitto-broker --network myNet -v $PWD/config/mosquitto.conf:/mosquitto/config/mosquitto.conf eclipse-mosquitto
      echo ""

      docker stats --format "{{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" mosquitto-broker |
                                           gxargs -d "\n" -L1 bash -c 'gdate "+%s%3N: $0"' |
        while IFS= read -r line
        do
          echo "$line"
        done > results_50_75/"$name".txt &

      echo "Logging started..."
      echo ""

      sleep 10
      echo "Starting publisher"
      docker run -t --rm --name bench-pub --network myNet flipperthedog/mqtt-bench mqtt-bench -action=pub -broker=$BROKER \
            -clients="${PUBLISHER[i]}" \
            -count=$MESSAGES  \
            -size="$size"   \
            -qos=$QOS \
            -intervaltime=$INTERVAL_TIME -pretime=$PRETIME -x &

      echo "Starting subscriber"
      docker run -t --rm --name bench-sub --network myNet flipperthedog/mqtt-bench mqtt-bench -action=sub -broker=$BROKER \
            -clients="${SUBSCRIBER[i]}" \
            -count=$((PUBLISHER[i]*MESSAGES-PUBLISHER[i]*2)) \
            -qos=$QOS \
            -intervaltime=$INTERVAL_TIME -pretime=0 -x -topic="/mqtt-bench/benchmark/#"

      echo ""

      sleep 30
      docker exec -t mosquitto-broker sh -c "ls -lh | awk '{print \$5}' | grep -E '^[0-9.]+[KMG]?$' | awk '
function human(x) {
    s=substr(x,length(x),1);
    v=substr(x,1,length(x)-1);
    return (s ~ /[KMG]/ ? v * (s ~ /K/ ? 1e3 : (s ~ /M/ ? 1e6 : 1e9)) : v)
}
{total += human(\$1)} END {print total}'" > results/total_container_"$name".txt
sleep 3

      docker exec -t mosquitto-broker ls -lh mosquitto/data/mosquitto.db | awk '{print $5}' > results_50_75/ls_"$name".txt &
      echo "Simulation $name done."
      sleep 30

      echo ""
      echo ""
    done
  done
  sleep 5
done
sleep 10
echo "Killing processes."
pkill -P $$