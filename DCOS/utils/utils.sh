#!/usr/bin/env bash

check_open_port() {
    #
    # Checks with a timeout if a particular port (TCP or UDP) is open (nc tool is used for this)
    #
    local ADDRESS="$1"
    local PORT="$2"
    local TIMEOUT=900
    SECONDS=0
    while true; do
        if [[ $SECONDS -gt $TIMEOUT ]]; then
            echo "ERROR: Port $PORT didn't open at $ADDRESS within $TIMEOUT seconds"
            return 1
        fi
        nc -w 5 -z "$ADDRESS" "$PORT" &>/dev/null && break || sleep 1
    done
}

run_ssh_command() {
    #
    # Run an SSH command
    #
    while [ $# -gt 0 ];
    do
        case $1 in
            -i)
                local SSH_KEY=$2
                shift;;
            -u)
                local REMOTE_USER=$2
                shift;;
            -h)
                local HOST=$2
                shift;;
            -p)
                local PORT=$2
                shift;;
            -c)
                local COMMAND=$2
                shift;;
            -t)
                local TIMEOUT=$2
                shift;;
            -*)
                local PARAM=$1
                echo "unknown parameter $PARAM"
                echo "$0 -i SSH_KEY -u REMOTE_USER -h HOST -p PORT -c COMMAND"
                return 1;;
        esac
        shift
    done
    if [[ -z $REMOTE_USER ]] || [[ -z $HOST ]] || [[ -z $COMMAND ]]; then
        echo "REMOTE_USER, HOST and COMMAND are mandatory"
        return 1
    fi
    if [ -z $PORT ]; then
        local PORT="22"
    fi
    if [ -z $SSH_KEY ]; then
        local SSH_KEY="$HOME/.ssh/id_rsa"
    fi
    if [ -z $TIMEOUT ]; then
        local TIMEOUT="30m"
    fi
    check_open_port $HOST $PORT || return 1
    timeout --signal SIGKILL $TIMEOUT ssh -o 'LogLevel=quiet' -o 'PasswordAuthentication=no' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i $SSH_KEY -p "$PORT" ${REMOTE_USER}@${HOST} "$COMMAND"
    if [[ $? -eq 137 ]]; then
        echo "ERROR: The timeout of $TIMEOUT is reached for the SSH command: ${REMOTE_USER}@${HOST} '${COMMAND}'"
        return 1
    fi
}

upload_files_via_scp() {
    #
    # Upload files via SCP
    #
    while [ $# -gt 0 ];
    do
        case $1 in
            -i)
                local SSH_KEY=$2
                shift;;
            -u)
                local REMOTE_USER=$2
                shift;;
            -h)
                local HOST=$2
                shift;;
            -p)
                local PORT=$2
                shift;;
            -t)
                local TIMEOUT=$2
                shift;;
            -f)
                local REMOTE_PATH=$2
                local LOCAL_PATH=$3
                shift;;
            -*)
                local PARAM=$1
                echo "unknown parameter $PARAM"
                echo "$0 -i SSH_KEY -u REMOTE_USER -h HOST -p PORT -f REMOTE_PATH LOCAL_PATH"
                return 1;;
        esac
        shift
    done
    if [[ -z $REMOTE_USER ]] || [[ -z $HOST ]] || [[ -z $LOCAL_PATH ]] || [[ -z $REMOTE_PATH ]]; then
        echo "REMOTE_USER, HOST, LOCAL_PATH and REMOTE_PATH are mandatory"
        return 1
    fi
    if [ -z $PORT ]; then
        local PORT="22"
    fi
    if [ -z $SSH_KEY ]; then
        local SSH_KEY="$HOME/.ssh/id_rsa"
    fi
    if [ -z $TIMEOUT ]; then
        local TIMEOUT="30m"
    fi
    check_open_port $HOST $PORT || return 1
    timeout --signal SIGKILL $TIMEOUT scp -r -P "$PORT" -o 'LogLevel=quiet' -o 'PasswordAuthentication=no' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i $SSH_KEY $LOCAL_PATH ${REMOTE_USER}@${HOST}:${REMOTE_PATH}
    if [[ $? -eq 137 ]]; then
        echo "ERROR: The timeout of $TIMEOUT is reached for the SCP command: $LOCAL_PATH ${REMOTE_USER}@${HOST}:${REMOTE_PATH}"
        return 1
    fi
}

download_files_via_scp() {
    #
    # Download files via SCP
    #
    while [ $# -gt 0 ];
    do
        case $1 in
            -i)
                local SSH_KEY=$2
                shift;;
            -u)
                local REMOTE_USER=$2
                shift;;
            -h)
                local HOST=$2
                shift;;
            -p)
                local PORT=$2
                shift;;
            -t)
                local TIMEOUT=$2
                shift;;
            -f)
                local REMOTE_PATH=$2
                local LOCAL_PATH=$3
                shift;;
            -*)
                local PARAM=$1
                echo "unknown parameter $PARAM"
                echo "$0 -i SSH_KEY -u REMOTE_USER -h HOST -p PORT -f REMOTE_PATH LOCAL_PATH"
                return 1;;
        esac
        shift
    done
    if [[ -z $HOST ]] || [[ -z $LOCAL_PATH ]] || [[ -z $REMOTE_PATH ]]; then
        echo "HOST, LOCAL_PATH and REMOTE_PATH are mandatory"
        return 1
    fi
    if [ -z $PORT ]; then
        local PORT="22"
    fi
    if [ -z $SSH_KEY ]; then
        local SSH_KEY="$HOME/.ssh/id_rsa"
    fi
    if [[ -z $REMOTE_USER ]]; then
        local REMOTE_USER="azureuser"
    fi
    if [ -z $TIMEOUT ]; then
        local TIMEOUT="30m"
    fi
    check_open_port $HOST $PORT || return 1
    timeout --signal SIGKILL $TIMEOUT scp -r -P "$PORT" -o 'LogLevel=quiet' -o 'PasswordAuthentication=no' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i $SSH_KEY ${REMOTE_USER}@${HOST}:${REMOTE_PATH} $LOCAL_PATH
    if [[ $? -eq 137 ]]; then
        echo "ERROR: The timeout of $TIMEOUT is reached for the SCP command: $LOCAL_PATH ${REMOTE_USER}@${HOST}:${REMOTE_PATH}"
        return 1
    fi
}

mount_smb_share() {
    #
    # Mount an SMB share (using version 3.0)
    #
    local HOST=$1
    local USER=$2
    local PASS=$3
    if mount | awk '{print $3}' | grep -q "^\/mnt\/${HOST}$"; then
        return 0
    fi
    sudo mkdir -p /mnt/$HOST || return 1
    sudo mount -t cifs //$HOST/C$ /mnt/$HOST -o username=$USER,password=$PASS,vers=3.0 || return 1
}

umount_smb_share(){
    #
    # Unmount an SMB share
    #
    local HOST=$1
    sudo umount /mnt/$HOST && sudo rmdir /mnt/$HOST
}
