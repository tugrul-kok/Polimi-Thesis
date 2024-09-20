echo '
import paho.mqtt.client as mqtt

# Callback when a message is received
def on_message(client, userdata, msg):
    print(f"Received message: {msg.payload.decode()} on topic {msg.topic}")

# MQTT Settings
broker = "192.168.100.10"  # Mosquitto broker IP
port = 1883
topic = "test/topic"

# Create an MQTT client instance using the latest version of the API
client = mqtt.Client(protocol=mqtt.MQTTv5)

# Define the on_message callback
client.on_message = on_message

# Connect to the broker
client.connect(broker, port, 60)

# Subscribe to the topic
client.subscribe(topic)

# Loop to wait for messages
client.loop_forever()
' > subscriber.py