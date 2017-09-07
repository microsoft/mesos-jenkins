#!/bin/bash

PYTHON_SCRIPT="/home/ubuntu/mesos-jenkins/Mesos/utils/verify-review-requests.py"
LOG_FILE="/home/ubuntu/logs/verify-review-requests-cron.log"

echo -e "\n$(date +%m-%d-%y-%T) - Running $PYTHON_SCRIPT" >> $LOG_FILE

ps aux | grep -v " grep " | grep -q "$PYTHON_SCRIPT" && echo -e "The script is already running\n" >> $LOG_FILE && exit 0

/usr/bin/python $PYTHON_SCRIPT -u '<user_name>' -p '<password>' \
                               gearman -s '10.3.1.4,10.3.1.8' -j 'mesos-build' \
                                       --params '{"BRANCH": "master"}' 2>&1 >> $LOG_FILE

echo -e "\n" >> $LOG_FILE
