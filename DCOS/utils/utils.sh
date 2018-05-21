#!/usr/bin/env bash

run_ssh_command() {
    #
    # Run an SSH command
    #
    while [ $# -gt 0 ];
    do
        case $1 in
            -i)
                SSH_KEY=$2
                shift;;
            -u)
                USER=$2
                shift;;
            -h)
                HOST=$2
                shift;;
            -p)
                PORT=$2
                shift;;
            -c)
                COMMAND=$2
                shift;;
            *)
                PARAM=$1
                echo "unknown parameter $PARAM"
                echo "$0 -i SSH_KEY -u USER -h HOST -p PORT -c COMMAND"
                exit 1;;
        esac
        shift
    done
    if [[ -z $USER ]] || [[ -z $HOST ]] || [[ -z $COMMAND ]]; then
        echo "USER, HOST and COMMAND are mandatory"
        exit 1
    fi
    if [ -z $PORT ]; then
        PORT="22"
    fi
    if [ -z $SSH_KEY ]; then
        KEY_PATH=""
    else
        KEY_PATH="-i $SSH_KEY"
    fi
    ssh -o 'LogLevel=quiet' -o 'PasswordAuthentication=no' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' $KEY_PATH -p "$PORT" ${USER}@${HOST} "$COMMAND"
}

upload_files_via_scp() {
    #
    # Upload files via SCP
    #
    while [ $# -gt 0 ];
    do
        case $1 in
            -i)
                SSH_KEY=$2
                shift;;
            -u)
                USER=$2
                shift;;
            -h)
                HOST=$2
                shift;;
            -p)
                PORT=$2
                shift;;
            -f)
                LOCAL_PATH=$2
                REMOTE_PATH=$3
                shift;;
            *)
                PARAM=$1
                echo "unknown parameter $PARAM"
                echo "$0 -i SSH_KEY -u USER -h HOST -p PORT -f LOCAL_PATH REMOTE_PATH"
                exit 1;;
        esac
        shift
    done
    if [[ -z $USER ]] || [[ -z $HOST ]] || [[ -z $LOCAL_PATH ]] || [[ -z $REMOTE_PATH ]]; then
        echo "USER, HOST, LOCAL_PATH and REMOTE_PATH are mandatory"
        exit 1
    fi
    if [ -z $PORT ]; then
        PORT="22"
    fi
    if [ -z $SSH_KEY ]; then
        KEY_PARAM=""
    else
        KEY_PARAM="-i $SSH_KEY"
    fi
    scp -r -P "$PORT" -o 'LogLevel=quiet' -o 'PasswordAuthentication=no' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' $KEY_PARAM $LOCAL_PATH ${USER}@${HOST}:${REMOTE_PATH}
}

download_files_via_scp() {
    #
    # Download files via SCP
    #
    while [ $# -gt 0 ];
    do
        case $1 in
            -i)
                SSH_KEY=$2
                shift;;
            -u)
                USER=$2
                shift;;
            -h)
                HOST=$2
                shift;;
            -p)
                PORT=$2
                shift;;
            -f)
                LOCAL_PATH=$2
                REMOTE_PATH=$3
                shift;;
            *)
                PARAM=$1
                echo "unknown parameter $PARAM"
                echo "$0 -i SSH_KEY -u USER -h HOST -p PORT -f LOCAL_PATH REMOTE_PATH"
                exit 1;;
        esac
        shift
    done
    if [[ -z $HOST ]] || [[ -z $LOCAL_PATH ]] || [[ -z $REMOTE_PATH ]]; then
        echo "USER, HOST, LOCAL_PATH and REMOTE_PATH are mandatory"
        exit 1
    fi
    if [ -z $PORT ]; then
        PORT="22"
    fi
    if [ -z $SSH_KEY ]; then
        KEY_PARAM=""
    else
        KEY_PARAM="-i $SSH_KEY"
    fi
    if [[ -z $USER ]]; then
        USER="azureuser"
    fi
    scp -r -P "$PORT" -o 'LogLevel=quiet' -o 'PasswordAuthentication=no' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' $KEY_PARAM ${USER}@${HOST}:${REMOTE_PATH} $LOCAL_PATH
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
