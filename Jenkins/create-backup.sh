#!/usr/bin/env bash
set -e

BACKUPS_DIR="/data/jenkins-backups"
BACKUP_NAME=$(date "+%m_%d_%y-%H_%M")
VOLUME_NAME="jenkins-data"
CONTAINER_NAME="jenkins"

# - Check if the Jenkins data volume exists
if [[ "$(docker volume ls -q | grep $VOLUME_NAME)" = "" ]]; then
    echo "ERROR: Docker volume $VOLUME_NAME doesn't exist"
    exit 1
fi

# - Check if the Jenkins container exists
if [[ "$(docker ps -a | grep "\s*${CONTAINER_NAME}$")" = "" ]]; then
    echo "ERROR: Docker container $CONTAINER_NAME doesn't exist"
    exit 1
fi

# - Create the backup dir
rm -rf $BACKUPS_DIR/$BACKUP_NAME
mkdir -p $BACKUPS_DIR/$BACKUP_NAME

# - Backup the Jenkins data volume
docker run --rm -v jenkins-data:/jenkins-data -v $BACKUPS_DIR/$BACKUP_NAME:/mnt alpine tar czf /mnt/jenkins-data.tar.gz jenkins-data

# - Backup the Jenkins container
docker save -o $BACKUPS_DIR/$BACKUP_NAME/jenkins-container.tar jenkinsbuild
gzip $BACKUPS_DIR/$BACKUP_NAME/jenkins-container.tar
