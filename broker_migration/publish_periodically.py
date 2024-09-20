echo '
import paho.mqtt.client as mqtt
import time

# MQTT Settings
broker = "192.168.100.10"  # IP address of the mosquitto-broker container
port = 1883
topic = "test/topic"

# Create an MQTT client instance
client = mqtt.Client()

# Connect to the broker
client.connect(broker, port, 60)

# Start a loop to publish messages periodically
try:
    while True:
        message = f"Hello from Publisher at {time.ctime()}"
        # Publish the message with QoS 1 and retain it
        client.publish(topic, message, qos=1, retain=True)
        print(f"Published: {message} | QoS: 1 | Retained")
        time.sleep(5)  # Publish every 5 seconds
except KeyboardInterrupt:
    print("Publishing stopped.")

# Disconnect from the broker
client.disconnect()
' > publish_periodically.py
