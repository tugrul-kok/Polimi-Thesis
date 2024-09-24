mkdir iperf_server_with_db
cd iperf_server_with_db

# Add these to a Dockerfile
FROM networkstatic/iperf3

# Set the working directory
WORKDIR /app

# Copy the fake database file into the image
COPY fake_database.db /app/fake_database.db

# Expose iperf3 server port
EXPOSE 5201

# Start the iperf3 server
ENTRYPOINT ["iperf3", "-s"]



dd if=/dev/urandom of=fake_database.db bs=1M count=5
docker build -t custom_iperf_server:latest .

