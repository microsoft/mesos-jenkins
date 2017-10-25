#!/usr/bin/env bash

run_ssh_command() {
    #
    # Run an SSH command
    #
    local USER="$1"
    local ADDRESS="$2"
    local PORT="$3"
    local CMD="$4"
    ssh -o 'PasswordAuthentication=no' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -p "$PORT" $USER@$ADDRESS "$CMD"
}

upload_files_via_scp() {
    #
    # Upload files via SCP
    #
    local USER="$1"
    local ADDRESS="$2"
    local PORT="$3"
    local REMOTE_PATH="$4"
    local LOCAL_PATH="$5"
    scp -r -P "$PORT" -o 'PasswordAuthentication=no' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' $LOCAL_PATH $USER@$ADDRESS:$REMOTE_PATH
}

download_files_via_scp() {
    #
    # Download files via SCP
    #
    local ADDRESS="$1"
    local PORT="$2"
    local REMOTE_PATH="$3"
    local LOCAL_PATH="$4"
    local USER="$5"
    if [[ -z $USER ]]; then
        USER="azureuser"
    fi
    scp -r -P "$PORT" -o 'PasswordAuthentication=no' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' $USER@$ADDRESS:$REMOTE_PATH $LOCAL_PATH
}

mount_smb_share() {
    #
    # Mount an SMB share (using version 3.0)
    #
    local HOST=$1
    local USER=$2
    local PASS=$3
    sudo mkdir -p /mnt/$HOST
    sudo mount -t cifs //$HOST/C$ /mnt/$HOST -o username=$USER,password=$PASS,vers=3.0
}

umount_smb_share(){
    #
    # Unmount an SMB share
    #
    local HOST=$1
    sudo umount /mnt/$HOST
    sudo rmdir /mnt/$HOST
}
