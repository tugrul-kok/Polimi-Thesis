#!/usr/bin/env python3

import os
import time
import logging
from datetime import datetime
import paho.mqtt.client as mqtt

# Setup logging
logging.basicConfig(
    level=logging.DEBUG,  # Set to DEBUG for detailed logs
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/logs/client.log"),
        logging.StreamHandler()
    ]
)

logging.info("Client started...")

BROKER_IP = os.environ.get('BROKER_IP')
if not BROKER_IP:
    logging.error("BROKER_IP environment variable is not set.")
    exit(1)

END_TIME = time.time() + 10000  # Run for 5 minutes
DOWNTIME_TOTAL = 0
connected = False
disconnect_time = None

# Ensure the logs directory exists
if not os.path.exists('/logs'):
    os.makedirs('/logs')

downtime_log = open('/logs/downtime_log.txt', 'a', buffering=1)

def on_connect(client, userdata, flags, rc):
    global connected, DOWNTIME_TOTAL, disconnect_time
    logging.info(f"Connected with result code {rc}")
    if rc == 0:
        if not connected:
            if disconnect_time:
                reconnect_time = time.time()
                downtime = reconnect_time - disconnect_time
                DOWNTIME_TOTAL += downtime
                log_message = f"Reconnected at {datetime.now()} after {downtime:.2f} seconds of downtime"
                logging.info(log_message)
                downtime_log.write(log_message + '\n')
                downtime_log.flush()
                disconnect_time = None
            connected = True
    else:
        log_message = f"Failed to connect, return code {rc}"
        logging.error(log_message)
        downtime_log.write(log_message + '\n')
        downtime_log.flush()

def on_disconnect(client, userdata, rc):
    global connected, disconnect_time
    logging.warning(f"Disconnected with result code {rc}")
    if rc != 0:
        logging.warning("Unexpected disconnection, attempting to reconnect")
    if connected:
        disconnect_time = time.time()
        log_message = f"Disconnected at {datetime.now()}"
        logging.warning(log_message)
        downtime_log.write(log_message + '\n')
        downtime_log.flush()
        connected = False


def on_publish(client, userdata, mid):
    pass  # You can add logging here if needed

client = mqtt.Client(client_id="unique_client_id", clean_session=False)
client.on_connect = on_connect
client.on_disconnect = on_disconnect
client.on_publish = on_publish

client.enable_logger()

# Set automatic reconnect attempts
client.reconnect_delay_set(min_delay=0, max_delay=60)

# Connect to the broker
client.connect(BROKER_IP, 1883, keepalive=300)

# Start the loop in a separate thread
client.loop_start()

# Publish a retained message to ensure data is persisted
logging.info("Publishing retained message...")
client.publish('test/topic', payload='Retained message', qos=1, retain=False)

try:
    while time.time() < END_TIME:
        if connected:
            message = f"Test message at {datetime.now()}"
            logging.info(f"Publishing: {message}")
            client.publish('test/topic', payload=message, qos=1)
        else:
            logging.info("Client is disconnected, waiting to reconnect...")
        time.sleep(1)
except Exception as e:
    logging.error(f"An error occurred: {e}")
    downtime_log.write(f"An error occurred: {e}\n")
finally:
    client.loop_stop()
    client.disconnect()

    if not connected:
        log_message = "Client did not reconnect before the end of the test."
        logging.warning(log_message)
        downtime_log.write(log_message + '\n')

    log_message = f"Total downtime: {DOWNTIME_TOTAL:.2f} seconds"
    logging.info(log_message)
    downtime_log.write(log_message + '\n')

    downtime_log.close()

    # Write total downtime to a file
    with open('/logs/downtime_log.txt', 'w') as f:
        f.write(f"{DOWNTIME_TOTAL:.2f}")

    # Verify retained message
    logging.info("Subscribing to topic to verify retained message...")

    def on_message(client, userdata, msg):
        with open('/logs/retained_message.txt', 'w') as f:
            f.write(msg.payload.decode())
        client.disconnect()

    client = mqtt.Client()
    client.on_message = on_message
    client.connect(BROKER_IP, 1883, 60)
    client.subscribe('test/topic', qos=1)
    client.loop_forever()
