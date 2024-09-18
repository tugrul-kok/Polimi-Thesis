import paho.mqtt.client as mqtt
import pandas as pd
import json
import os

# MQTT Settings
BROKER = "localhost"
PORT = 1883
TOPIC = "iperf/results"
QOS = 1
CLIENT_ID = "iperf-subscriber-001"

# Filepath for the CSV
csv_file = 'iperf_results.csv'

# DataFrame columns
columns = [
    'timestamp', 'sent_bitrate', 'received_bitrate', 'jitter_ms', 'packet_loss',
    'total_bytes_sent', 'total_bytes_received', 'cpu_host_total', 'cpu_host_user',
    'cpu_host_system', 'cpu_remote_total', 'cpu_remote_user', 'cpu_remote_system',
    'tcp_congestion'
]

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
        jitter_ms = iperf_result['end'].get('jitter_ms', None)
        packet_loss = iperf_result['end'].get('lost_percent', None)

        # New data: total bytes sent/received
        total_bytes_sent = iperf_result['end']['sum_sent']['bytes']
        total_bytes_received = iperf_result['end']['sum_received']['bytes']

        # New data: CPU utilization
        cpu_host_total = iperf_result['end']['cpu_utilization_percent']['host_total']
        cpu_host_user = iperf_result['end']['cpu_utilization_percent']['host_user']
        cpu_host_system = iperf_result['end']['cpu_utilization_percent']['host_system']
        cpu_remote_total = iperf_result['end']['cpu_utilization_percent']['remote_total']
        cpu_remote_user = iperf_result['end']['cpu_utilization_percent']['remote_user']
        cpu_remote_system = iperf_result['end']['cpu_utilization_percent']['remote_system']

        # New data: TCP congestion control algorithm
        tcp_congestion = iperf_result['end'].get('receiver_tcp_congestion', None)

        # Create a new row with the parsed data
        new_row = {
            'timestamp': timestamp,
            'sent_bitrate': sent_bitrate,
            'received_bitrate': received_bitrate,
            'jitter_ms': jitter_ms,
            'packet_loss': packet_loss,
            'total_bytes_sent': total_bytes_sent,
            'total_bytes_received': total_bytes_received,
            'cpu_host_total': cpu_host_total,
            'cpu_host_user': cpu_host_user,
            'cpu_host_system': cpu_host_system,
            'cpu_remote_total': cpu_remote_total,
            'cpu_remote_user': cpu_remote_user,
            'cpu_remote_system': cpu_remote_system,
            'tcp_congestion': tcp_congestion
        }

        # Convert the new row to a DataFrame
        new_row_df = pd.DataFrame([new_row])

        # Check if the file exists, and if not, write the header
        if not os.path.isfile(csv_file):
            new_row_df.to_csv(csv_file, mode='w', header=True, index=False)
        else:
            new_row_df.to_csv(csv_file, mode='a', header=False, index=False)

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
