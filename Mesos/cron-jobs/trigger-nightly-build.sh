#!/usr/bin/env bash

if [[ $# -ne 1 ]]; then
    echo "USAGE: $0 <cron_job_parameters_file>"
    exit 1
fi

source "$1" || (echo "ERROR: Failed to source the cron job parameters file" && exit 1)

if [[ -z $LOG_FILE ]]; then echo "ERROR: LOG_FILE environment variable was not set" ; exit 1 ; fi
if [[ -z $REVIEWBOARD_USER ]]; then echo "ERROR: REVIEWBOARD_USER environment variable was not set" ; exit 1 ; fi
if [[ -z $REVIEWBOARD_USER_PASSWORD ]]; then echo "ERROR: REVIEWBOARD_USER_PASSWORD environment variable was not set" ; exit 1 ; fi
if [[ -z $JENKINS_SERVERS ]]; then echo "ERROR: JENKINS_SERVERS environment variable was not set" ; exit 1 ; fi
if [[ -z $JENKINS_CLI_JAR ]]; then echo "ERROR: JENKINS_CLI_JAR environment variable was not set" ; exit 1 ; fi
if [[ -z $JENKINS_JOB_NAME ]]; then echo "ERROR: JENKINS_JOB_NAME environment variable was not set" ; exit 1 ; fi
if [[ -z $JENKINS_SSH_KEY ]]; then echo "ERROR: JENKINS_SSH_KEY environment variable was not set" ; exit 1 ; fi
if [[ -z $JENKINS_EXECUTOR_TEMP_DIR ]]; then echo "ERROR: JENKINS_EXECUTOR_TEMP_DIR environment variable was not set" ; exit 1 ; fi

if [[ -e $JENKINS_EXECUTOR_TEMP_DIR ]]; then
    echo -e "$(date +%m-%d-%y-%T) - The script $0 is already running\n" >> $LOG_FILE
    exit 0
fi
mkdir -p $JENKINS_EXECUTOR_TEMP_DIR

DIR=$(dirname $0)
source $DIR/../utils/jenkins-executor-common.sh 2>&1 >> $LOG_FILE

start_workers() {
    if [[ -z $JENKINS_AVAILABLE_SERVERS ]]; then
        echo "ERROR: The JENKINS_AVAILABLE_SERVERS environment variable is not set"
        rm -rf $JENKINS_EXECUTOR_TEMP_DIR
        exit 1
    fi
    echo "Starting $JENKINS_JOB_NAME"
    echo "Jenkins servers used: ${JENKINS_AVAILABLE_SERVERS[*]}"
    start_worker
    wait_running_workers
    rm -rf $JENKINS_EXECUTOR_TEMP_DIR
    echo "All the workers finished executing their jobs"
}

set_available_jenkins_servers >> $LOG_FILE
start_workers >> $LOG_FILE

echo -e "\n" >> $LOG_FILE
