import paho.mqtt.client as mqtt
import pandas as pd
import json

# MQTT Settings
BROKER = "localhost"
PORT = 1883
TOPIC = "iperf/results"
QOS = 1
CLIENT_ID = "iperf-subscriber-001"

# Callback when the client connects to the broker
def on_connect(client, userdata, flags, rc):
    print(f"Connected with result code {rc}")
    client.subscribe(TOPIC, qos=QOS)

# Callback when a message is received
def on_message(client, userdata, msg):
    try:
        # Decode the payload
        payload = msg.payload.decode("utf-8")
        
        # Check if the payload is not empty
        if not payload.strip():
            print("Received empty message, skipping.")
            return

        # Parse the message payload as JSON
        iperf_result = json.loads(payload)

        # Extract relevant data from iPerf JSON output
        timestamp = iperf_result['start']['timestamp']['timesecs']
        sent_bitrate = iperf_result['end']['sum_sent']['bits_per_second'] / 1e6  # Convert to Mbps
        received_bitrate = iperf_result['end']['sum_received']['bits_per_second'] / 1e6  # Convert to Mbps
        jitter_ms = iperf_result['end'].get('jitter_ms', None)  # Get jitter if available
        packet_loss = iperf_result['end'].get('lost_percent', None)  # Get packet loss if available

        # Create a new row with the parsed data
        new_row = {
            'timestamp': timestamp,
            'sent_bitrate': sent_bitrate,
            'received_bitrate': received_bitrate,
            'jitter_ms': jitter_ms,
            'packet_loss': packet_loss
        }

        # Create a DataFrame for this single message
        df = pd.DataFrame([new_row])

        # Save the DataFrame to a CSV file (append mode)
        df.to_csv('iperf_results.csv', mode='a', header=not pd.read_csv('iperf_results.csv').empty, index=False)

        print(f"Message processed and saved: {new_row}")

    except json.JSONDecodeError:
        print(f"Error processing message: Invalid JSON format in message: {payload}")
    except Exception as e:
        print(f"Error processing message: {e}")

# Create an MQTT client instance with a client ID
client = mqtt.Client(client_id=CLIENT_ID, clean_session=True)

# Assign callback functions
client.on_connect = on_connect
client.on_message = on_message

# Connect to the MQTT broker
client.connect(BROKER, PORT, 60)

# Start a loop to keep the client connected and processing messages
client.loop_forever()
