import paho.mqtt.client as mqtt
import time

# MQTT Settings
BROKER = "localhost"
PORT = 1883
TOPIC = "test/iperf"
QOS = 1
CLIENT_ID = "mqtt-iperf-client"
PUBLISH_INTERVAL = 0.5  # Time between messages in seconds

# The callback when the client connects to the broker
def on_connect(client, userdata, flags, rc):
    print(f"Connected to broker with result code {rc}")
    client.subscribe(TOPIC)

# Create an MQTT client instance
client = mqtt.Client(client_id=CLIENT_ID)
client.on_connect = on_connect

# Connect to the MQTT broker
client.connect(BROKER, PORT, 60)

# Start the loop
client.loop_start()

# Continuously publish messages
try:
    start_time = time.time()
    while time.time() - start_time < 60:  # Run for 60 seconds
        message = f"Test message at {time.time()}"
        client.publish(TOPIC, message, qos=QOS)
        print(f"Published: {message}")
        time.sleep(PUBLISH_INTERVAL)

except KeyboardInterrupt:
    print("Publishing stopped.")

# Stop the loop and disconnect
client.loop_stop()
client.disconnect()
