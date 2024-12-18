#!/bin/bash

# Ensure BROKER_IP is set
if [ -z "$BROKER_IP" ]; then
    echo "BROKER_IP environment variable is not set."
    exit 1
fi

END_TIME=$(( $(date +%s) + 300 ))  # Run for 5 minutes
connected=true
DOWNTIME_TOTAL=0

# Publish a retained message to ensure data is persisted
echo "Publishing retained message..."
mosquitto_pub -h $BROKER_IP -t 'test/topic' -m 'Retained message' -r -d

while [ $(date +%s) -lt $END_TIME ]; do
    echo "Publishing test message at $(date)..."
    mosquitto_pub -h $BROKER_IP -t 'test/topic' -m 'Test message' -d
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        if [ "$connected" = true ]; then
            DISCONNECT_TIME=$(date +%s)
            echo "Disconnected at $(date)" | tee -a /logs/downtime_log.txt
            connected=false
        fi
    else
        if [ "$connected" = false ]; then
            RECONNECT_TIME=$(date +%s)
            DOWNTIME=$(( RECONNECT_TIME - DISCONNECT_TIME ))
            DOWNTIME_TOTAL=$(( DOWNTIME_TOTAL + DOWNTIME ))
            echo "Reconnected at $(date) after $DOWNTIME seconds of downtime" | tee -a /logs/downtime_log.txt
            connected=true
        fi
    fi
    sleep 1
done

if [ "$connected" = false ]; then
    echo "Client did not reconnect before the end of the test." | tee -a /logs/downtime_log.txt
fi

echo "Total downtime: $DOWNTIME_TOTAL seconds" | tee -a /logs/downtime_log.txt
echo $DOWNTIME_TOTAL > /logs/downtime_total.txt
sync /logs/downtime_total.txt

# Subscribe to the topic and print messages to verify persistence
echo "Subscribing to topic to verify retained message..."
mosquitto_sub -h $BROKER_IP -t 'test/topic' -C 1 -d > /logs/retained_message.txt
