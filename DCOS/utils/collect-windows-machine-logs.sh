#!/usr/bin/env bash
set -e

if [[ $# -ne 4 ]]; then
    echo "USAGE: $0 <tmp_logs_dir> <machine_address> <machine_user> <machine_password>"
    exit 1
fi

TMP_LOGS_DIR="$1"
ADDRESS="$2"
USER="$3"
PASSWORD="$4"

DIR=$(dirname $0)
source $DIR/utils.sh

rm -rf $TMP_LOGS_DIR
mkdir -p $TMP_LOGS_DIR

# Mount the Windows machine
mount_smb_share $ADDRESS $USER $PASSWORD

# Copy the C:\AzureData logs
cp -rf /mnt/$ADDRESS/AzureData $TMP_LOGS_DIR/

# Copy all the existing machine logs
for SERVICE in "epmd" "mesos" "diagnostics" "dcos-net"; do
    SERVICE_DIR="/mnt/$ADDRESS/DCOS/$SERVICE"
    if [[ ! -d $SERVICE_DIR ]]; then
        continue
    fi
    mkdir -p $TMP_LOGS_DIR/$SERVICE
    if [[ -e $SERVICE_DIR/log ]]; then
        cp -rf $SERVICE_DIR/log $TMP_LOGS_DIR/$SERVICE/
    fi
    if [[ -e $SERVICE_DIR/service/environment-file ]]; then
        cp $SERVICE_DIR/service/environment-file $TMP_LOGS_DIR/$SERVICE/
    fi
done
for ITEM in "/mnt/$ADDRESS/DCOS/environment" \
            "/mnt/$ADDRESS/Program Files/Docker/dockerd.log" \
            "/mnt/$ADDRESS/var/log" \
            "/mnt/$ADDRESS/etc"; do
    if [[ -e "$ITEM" ]]; then
        cp -rf "$ITEM" $TMP_LOGS_DIR/
    fi
done
if [[ -e "/mnt/$ADDRESS/opt/mesosphere/etc" ]]; then
    cp -rf "/mnt/$ADDRESS/opt/mesosphere/etc" $TMP_LOGS_DIR/mesosphere-etc
fi
