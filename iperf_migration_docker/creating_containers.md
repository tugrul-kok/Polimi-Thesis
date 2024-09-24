# Creating fake db
dd if=/dev/urandom of=fake_database.db bs=1M count=5

# Building the first server image
docker build -t custom_iperf_server_first -f Dockerfile.first .

# Building the second server image
docker build -t custom_iperf_server_second -f Dockerfile.second .

