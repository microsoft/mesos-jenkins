#!/usr/bin/env bash
set -e

if [[ -z $JENKINS_CLI_JAR ]]; then echo "ERROR: JENKINS_CLI_JAR environment variable is not set"; exit 1; fi
if [[ -z $JENKINS_JOB_NAME ]]; then echo "ERROR: JENKINS_JOB_NAME environment variable is not set"; exit 1; fi
if [[ -z $JENKINS_SSH_KEY ]]; then echo "ERROR: JENKINS_SSH_KEY environment variable is not set"; exit 1; fi
if [[ -z $JENKINS_SERVERS ]]; then echo "ERROR: JENKINS_SERVERS environment variable is not set"; exit 1; fi
if [[ -z $JENKINS_EXECUTOR_TEMP_DIR ]]; then echo "ERROR: JENKINS_EXECUTOR_TEMP_DIR environment variable is not set"; exit 1; fi


set_available_jenkins_servers() {
    #
    # Sets the global variable: JENKINS_AVAILABLE_SERVERS
    # This is a list of the Jenkins servers that are available to be used
    # It is mandatory to pass the Jenkins servers as the first argument to this
    # function.
    # 
    # Function usage:
    #   set_available_jenkins_servers "10.3.1.4:8080,10.3.1.8:8080"
    #
    JENKINS_AVAILABLE_SERVERS=()
    for SERVER in $(echo $JENKINS_SERVERS | sed "s|,|\n|g"); do
        ADDRESS=$(echo $SERVER | cut -d ':' -f1)
        PORT=$(echo $SERVER | cut -d ':' -f2)
        nc -z $ADDRESS $PORT && JENKINS_AVAILABLE_SERVERS=("${JENKINS_AVAILABLE_SERVERS[@]}" $SERVER) || echo "WARNING: Server $SERVER is not available"
    done
    if [[ ${#JENKINS_AVAILABLE_SERVERS[@]} -eq 0 ]]; then
        echo "ERROR: None of the Jenkins servers is available to be used"
        rm -rf $JENKINS_EXECUTOR_TEMP_DIR
        exit 1
    fi
}

wait_for_available_server() {
    #
    # This function iterates over the JENKINS_EXECUTOR_TEMP_DIR to see if any process
    # of an executor is finished. If the process is finished, it means that the
    # worker finished its execution and we return the worker's server address.
    #
    local SERVER=""
    while true; do
        for PID in $(ls $JENKINS_EXECUTOR_TEMP_DIR); do
            if ! ps -p $PID > /dev/null; then
                # This means that worker process ended and the server used by the worker
                # is available again.
                SERVER=$(cat $JENKINS_EXECUTOR_TEMP_DIR/$PID)
                rm -f $JENKINS_EXECUTOR_TEMP_DIR/$PID
                break
            fi
        done
        if [[ "$SERVER" != "" ]]; then
            echo $SERVER
            return 0
        fi
        sleep 5
    done
}

start_worker() {
    #
    # This function starts a Jenkins worker in background on the first
    # available Jenkins server
    #
    local JENKINS_JOB_PARAMS="$1"
    if [[ ${#JENKINS_AVAILABLE_SERVERS[@]} -eq 0 ]]; then
        SERVER=$(wait_for_available_server)
        JENKINS_AVAILABLE_SERVERS=("${JENKINS_AVAILABLE_SERVERS[@]}" $SERVER)
    fi
    SERVER=${JENKINS_AVAILABLE_SERVERS[0]}
    JENKINS_AVAILABLE_SERVERS=("${JENKINS_AVAILABLE_SERVERS[@]:1}")
    MSG="Started worker on the server $SERVER"
    JENKINS_CLI_PARAMS=""
    if [[ ! -z $JENKINS_JOB_PARAMS ]]; then
        JENKINS_CLI_PARAMS="-p $(echo $JENKINS_JOB_PARAMS | sed "s/,/ -p /g")"
        MSG="$MSG with parameters: $JENKINS_JOB_PARAMS"
    fi
    nohup java -jar $JENKINS_CLI_JAR -i $JENKINS_SSH_KEY -s "http://$SERVER/" build $JENKINS_JOB_NAME -s $JENKINS_CLI_PARAMS &>/dev/null &
    PID=$!
    echo $MSG
    echo $SERVER > $JENKINS_EXECUTOR_TEMP_DIR/$PID
}

wait_running_workers() {
    #
    # This function iterates over the JENKINS_EXECUTOR_TEMP_DIR and waits
    # until all the workers processes are finished
    #
    if [[ $(ls $JENKINS_EXECUTOR_TEMP_DIR | wc -l) -eq 0 ]]; then
        # There are 0 running workers
        return 0
    fi
    while [[ $(ls $JENKINS_EXECUTOR_TEMP_DIR | wc -l) -gt 0 ]]; do
        wait_for_available_server > /dev/null
    done
}
