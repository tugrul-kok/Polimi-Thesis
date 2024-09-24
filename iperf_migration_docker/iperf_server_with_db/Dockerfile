FROM networkstatic/iperf3

# Set the working directory
WORKDIR /app

# Copy the fake database file into the image
COPY fake_database.db /app/fake_database.db

# Expose iperf3 server port
EXPOSE 5201

# Start the iperf3 server
ENTRYPOINT ["iperf3", "-s"]

