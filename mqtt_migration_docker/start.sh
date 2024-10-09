#!/bin/bash

# Start SSH daemon in the background
/usr/sbin/sshd

# Ensure that the ownership of the persistence directory is correct
chown -R mosquitto:mosquitto /mosquitto

# Start Mosquitto broker in the foreground
exec mosquitto -c /etc/mosquitto/mosquitto.conf
