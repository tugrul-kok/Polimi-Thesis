#!/bin/bash

# Start SSH daemon in the background
/usr/sbin/sshd

# Start iperf3 server in the foreground
exec iperf3 -s

