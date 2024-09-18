import paho.mqtt.client as mqtt
import subprocess

# Define the MQTT broker address and port
BROKER = "localhost"
PORT = 1883
TOPIC = "iperf/results"

# Run the iPerf client and capture the output
result = subprocess.run(["iperf3", "-c", "127.0.0.1"], stdout=subprocess.PIPE)

# Extract the relevant result data
iperf_output = result.stdout.decode('utf-8')

# Create an MQTT client instance
client = mqtt.Client()

# Connect to the broker
client.connect(BROKER, PORT, 60)

# Publish the iPerf result to the broker
client.publish(TOPIC, iperf_output)

# Disconnect after publishing
client.disconnect()
