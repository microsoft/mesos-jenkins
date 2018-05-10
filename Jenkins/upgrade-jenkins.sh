#!/usr/bin/env bash
set -e

CONTAINER_NAME="jenkins"
VOLUME_NAME="jenkins-data"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# - Remove existing container
if [[ "$(docker ps -a | grep "\s*${CONTAINER_NAME}$")" != "" ]]; then
    docker rm -f $CONTAINER_NAME
fi

# - Remove current Docker Jenkins custom & base image
for IMAGE in jenkinsbuild jenkins/jenkins; do
    IMAGE_ID=$(docker image ls $IMAGE -q)
    if [[ "$IMAGE_ID" != "" ]]; then
        docker image rm "$IMAGE_ID"
    fi
done

# - Create the Jenkins Docker image from jenkins/jenkins:lts base image
docker build --no-cache -t jenkinsbuild .

# - Run the Jenkins container
docker run --detach --restart unless-stopped --volume $VOLUME_NAME:/var/jenkins_home \
           --publish 50000:50000 --publish 8080:8080 \
           --name jenkins jenkinsbuild

