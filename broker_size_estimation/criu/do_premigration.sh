#!/bin/bash

FOLDER_NAME=$1
INTERVAL=$2
LAST=false
i=0;

while true
do
    echo "============================="
    echo "Iteration Number $i"
    echo "Doing the checkpoint..."
    start_checkpoint=$(date -u +%s.%6N)
    sudo podman container checkpoint --leave-running --tcp-established --export "$FOLDER_NAME"/"$i"_checkpoint.tar.gz mosquitto-broker
    elapsed_checkpoint="$(bc <<<"$(date -u +%s.%6N)-$start_checkpoint")"

    echo "Saving the database..."
    start_copy=$(date +%s.%6N)
    podman cp mosquitto-broker:/mosquitto/data/mosquitto.db "$FOLDER_NAME"/"$i"_database.db

    echo "Dumping the database..."
    /Users/tugrul/Desktop/Tez/my_migration/mosquitto/apps/db_dump/mosquitto_db_dump $(pwd)/"$FOLDER_NAME"/"$i"_database.db > "$FOLDER_NAME"/"$i"_db.txt
    if [ $i -gt 0 ]
    then
      echo -ne "Doing the difference... "
      diff "$FOLDER_NAME"/"$i"_db.txt  "$FOLDER_NAME"/"$((i-1))"_db.txt > "$FOLDER_NAME"/diff_"$i".txt
      echo "Done."
    fi
    LAST="$i"_database.db
    elapsed_copy="$(bc <<<"$(date -u +%s.%6N)-$start_copy")"

    echo $elapsed_copy
    echo $elapsed_checkpoint

    ((i++));
    sleep $INTERVAL
done