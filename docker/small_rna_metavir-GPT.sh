#!/bin/bash

# Check if both file path arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <file_path_1> <file_path_2>"
    exit 1
fi

# Define image name and container name
image_name="your_docker_image_name"
container_name="your_container_name"

# Check if the Docker image exists
if ! docker image inspect "$image_name" &> /dev/null; then
    echo "Image $image_name does not exist. Building the image..."
    # You can customize the image build or pull command here
    # For example, to pull from a registry: docker pull your_registry/$image_name
    # Or to build from a Dockerfile: docker build -t "$image_name" .
fi

# Start the Docker container with volumes mapped
docker run -d --name "$container_name" -v "$1":/path/in/container/file1 -v "$2":/path/in/container/file2 "$image_name"

# Execute a command inside the running container
docker exec "$container_name" your_command_here

# To stop and remove the container after running the command:
# docker stop "$container_name"
# docker rm "$container_name"
