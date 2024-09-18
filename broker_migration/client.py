import paho.mqtt.client as mqtt
import time

# Define the MQTT broker address and port
BROKER = "localhost"
PORT = 1883
TOPIC = "iperf/results"
QOS = 1
CLIENT_ID = "iperf-client-001"  # Unique client ID
PUBLISH_INTERVAL = 10  # Time in seconds between each publish
RUNNING_TIME = 60  # Total time in seconds to keep publishing messages

# The callback function when the client connects to the broker
def on_connect(client, userdata, flags, rc):
    print(f"Connected with result code {rc}")
    if rc == 0:
        print("Connection successful")
    else:
        print(f"Connection failed with code {rc}")

# The callback function when the client disconnects from the broker
def on_disconnect(client, userdata, rc):
    print(f"Disconnected with result code {rc}")

# The callback function when a message is published
def on_publish(client, userdata, mid):
    print(f"Message {mid} published.")

# Create an MQTT client instance with a client ID
client = mqtt.Client(client_id=CLIENT_ID, clean_session=False)  # Enable persistent session

# Assign callback functions
client.on_connect = on_connect
client.on_disconnect = on_disconnect
client.on_publish = on_publish

# Connect to the broker
client.connect(BROKER, PORT, 60)

# Start a loop to keep the client connected
client.loop_start()

# Publish messages periodically
start_time = time.time()

while time.time() - start_time < RUNNING_TIME:
    message = f"iperf test results at {time.time()}"
    result = client.publish(TOPIC, message, qos=QOS, retain=False)
    
    # Wait for the publish interval before sending the next message
    time.sleep(PUBLISH_INTERVAL)

# After the loop, stop the loop and disconnect
client.loop_stop()
client.disconnect()
