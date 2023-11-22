#!/bin/bash

# # Check if both file path arguments are provided
# if [ "$#" -ne 2 ]; then
#     echo "Usage: $0 <file_path_1> <file_path_2>"
#     exit 1
# fi

# Define image name and container name
image_name="small_rna_metavir"
container_name="small_rna_metavir"

# Check if the Docker image exists
if ! docker image inspect "$image_name" &> /dev/null; then
    echo "Image '$image_name' does not exist. Building the image..."
    docker build . --target=small_rna_metavir -t small_rna_metavir
fi

# Start the Docker container with volumes mapped
docker run -d --name "$container_name" -v "$1":/path/in/container/file1 -v "$2":/path/in/container/file2 "$image_name"

# Execute a command inside the running container
docker exec "$container_name" your_command_here

# To stop and remove the container after running the command:
# docker stop "$container_name"
# docker rm "$container_name"



docker run \
    -d -t \
    --name perl \
    -v .:/src \
    perl:5.16.3


docker run 
    -d 
    --name "$container_name" 
    -v "$1":/path/in/container/file1 
    -v "$2":/path/in/container/file2 
    "$image_name"