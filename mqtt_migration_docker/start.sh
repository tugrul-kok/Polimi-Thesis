#!/bin/bash

# Start SSH daemon in the background
/usr/sbin/sshd

# Start Mosquitto broker in the foreground
exec mosquitto -c /etc/mosquitto/mosquitto.conf

