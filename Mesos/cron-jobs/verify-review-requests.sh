#!/usr/bin/env bash

if [[ $# -ne 1 ]]; then
    echo "USAGE: $0 <cron_job_parameters_file>"
    exit 1
fi

source "$1" || (echo "ERROR: Failed to source the cron job parameters file" && exit 1)

if [[ -z $LOGS_DIR ]]; then echo "ERROR: LOGS_DIR environment variable was not set" ; exit 1 ; fi
if [[ -z $REVIEWBOARD_USER ]]; then echo "ERROR: REVIEWBOARD_USER environment variable was not set" ; exit 1 ; fi
if [[ -z $REVIEWBOARD_USER_PASSWORD ]]; then echo "ERROR: REVIEWBOARD_USER_PASSWORD environment variable was not set" ; exit 1 ; fi
if [[ -z $GEARMAN_SERVERS_LIST ]]; then echo "ERROR: GEARMAN_SERVERS_LIST environment variable was not set" ; exit 1 ; fi

DIR=$(dirname $0)
PYTHON_SCRIPT=$(realpath "$DIR/../utils/verify-review-requests.py") || (echo "ERROR: Failed to get the absolute path for verify-review-requests.py" && exit 1)
LOG_FILE=$(realpath "$LOGS_DIR/cron-mesos-verify-review-requests.log") || (echo "ERROR: Failed to get the absolute path for cron-mesos-verify-review-requests.log" && exit 1)

ps aux | grep -v " grep " | grep -q "$PYTHON_SCRIPT" && echo -e "The script is already running\n" >> $LOG_FILE && exit 0

python $PYTHON_SCRIPT -u "$REVIEWBOARD_USER" -p "$REVIEWBOARD_USER_PASSWORD" \
                      gearman -s "$GEARMAN_SERVERS_LIST" -j 'mesos-build' --params '{"BRANCH": "master"}' 2>&1 >> $LOG_FILE

echo -e "\n" >> $LOG_FILE
