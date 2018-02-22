#!/usr/bin/env bash
set -e

BACKUPS_DIR="/data/jenkins-backups"

# - Check if the backups directory exists
if [[ ! -d $BACKUPS_DIR ]]; then
    echo "ERROR: Backups directory $BACKUPS_DIR doesn't exist"
    exit 1
fi

VOLUME_NAME="jenkins-data"
CONTAINER_NAME="jenkins"

# - If the backup dir name is not passed, get the most recent backup
if [[ "$1" != "" ]]; then
    BACKUP_DIR_NAME="$1"
else
    BACKUP_DIR_NAME=$(ls -t $BACKUPS_DIR | head -1)
fi

echo "Restoring backup: $BACKUP_DIR_NAME"

# - Check if the backup directory exists
BACKUP_DIR="$BACKUPS_DIR/$BACKUP_DIR_NAME"
if [[ ! -d $BACKUP_DIR ]]; then
    echo "ERROR: Backup directory $BACKUP_DIR doesn't exist"
    exit 1
fi

# - Remove existing container
if [[ "$(docker ps -a | grep "\s*${CONTAINER_NAME}$")" != "" ]]; then
    docker rm -f $CONTAINER_NAME
fi

# - Remove existing volume (this command exists successfully even if the volume doesn't already exist)
docker volume rm -f $VOLUME_NAME

# - Create temp restore backup dir
TMP_DIR="/tmp/restore_backup_tmp_dir"
rm -rf $TMP_DIR
cp -rf $BACKUP_DIR $TMP_DIR
pushd $TMP_DIR

# - Create new Jenkins data named volume and populate with data from the backup
tar xzf jenkins-data.tar.gz
docker volume create $VOLUME_NAME
TMP_CONTAINER_NAME="restore-jenkins-backup-helper"
docker run -v $VOLUME_NAME:/data --name $TMP_CONTAINER_NAME alpine true
docker cp jenkins-data/. $TMP_CONTAINER_NAME:/data
docker rm -f $TMP_CONTAINER_NAME

# Create new Jenkins container from the backup
gunzip jenkins-container.tar.gz
docker load -i jenkins-container.tar
docker run --detach --restart unless-stopped --volume $VOLUME_NAME:/var/jenkins_home \
           --publish 50000:50000 --publish 8080:8080 \
           --name jenkins jenkinsbuild

# - Cleanup temp restore backup dir
popd
rm -rf $TMP_DIR

echo "Successfully restored backup: $BACKUP_DIR_NAME"
