# Use the official Golang image as the base for building the binary
FROM golang:1.17 AS builder

# Set the working directory inside the container
WORKDIR /app

# Copy the source code into the container
COPY . .

# Disable CGO and build the mqtt-bench binary statically
RUN CGO_ENABLED=0 GOOS=linux go build -o mqtt-bench mqtt-bench.go

# Use a minimal base image for the final container
FROM alpine:3.14

# Copy the built binary from the builder stage
COPY --from=builder /app/mqtt-bench /mqtt-bench

# Set the entrypoint to the mqtt-bench binary
ENTRYPOINT ["/mqtt-bench"]
