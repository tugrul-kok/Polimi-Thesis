import paho.mqtt.client as mqtt
import subprocess
import time

# MQTT Settings
BROKER = "localhost"
PORT = 1883
TOPIC = "iperf/results"
QOS = 1
CLIENT_ID = "iperf-client-001"
PUBLISH_INTERVAL = 30  # Interval between iPerf tests (in seconds)
RUNNING_TIME = 300  # Total time to run (in seconds)

# The callback function when the client connects to the broker
def on_connect(client, userdata, flags, rc):
    print(f"Connected with result code {rc}")
    if rc == 0:
        print("Connection successful")
    else:
        print(f"Connection failed with code {rc}")

# The callback function when a message is published
def on_publish(client, userdata, mid):
    print(f"Message {mid} published.")

# Create an MQTT client instance with a client ID
client = mqtt.Client(client_id=CLIENT_ID, clean_session=False)

# Assign callback functions
client.on_connect = on_connect
client.on_publish = on_publish

# Connect to the MQTT broker
client.connect(BROKER, PORT, 60)

# Start a loop to keep the client connected
client.loop_start()

# Run iPerf tests and publish results periodically
start_time = time.time()

while time.time() - start_time < RUNNING_TIME:
    try:
        # Run iPerf3 test as client
        iperf_result = subprocess.run(["iperf3", "-c", "127.0.0.1", "-J"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        # Parse the iPerf result (JSON format)
        result_output = iperf_result.stdout.decode("utf-8")
        
        # Publish the iPerf result to MQTT broker
        client.publish(TOPIC, result_output, qos=QOS, retain=False)

        # Print the published message
        print(f"Published iPerf result: {result_output}")

    except subprocess.CalledProcessError as e:
        print(f"Error running iPerf: {e}")

    # Wait for the publish interval before running the next iPerf test
    time.sleep(PUBLISH_INTERVAL)

# Stop the loop and disconnect after the specified RUNNING_TIME
client.loop_stop()
client.disconnect()
