#!/bin/bash

PYTHON_SCRIPT="/home/ubuntu/ci-scripts/verify-review-requests.py"
LOG_FILE="/home/ubuntu/logs/verify-reviews-cron.log"

echo -e ">>>>>>> Time of the run: $(date +%m-%d-%y-%T) <<<<<<<\n" >> $LOG_FILE

ps aux | grep -v " grep " | grep -q "$PYTHON_SCRIPT" && echo -e "\nThe script $PYTHON_SCRIPT is already running\n\n\n" >> $LOG_FILE && exit 0

/usr/bin/python $PYTHON_SCRIPT -u 'mesos-review-windows' \
                               -p '@ZyddB*sE39xcKt4PXReWmt8b25YbjDajxGwv@V4q@Vkh^jZfy' \
                               gearman -s '10.3.1.4,10.3.1.8' \
                                       -j 'mesos-build' \
                                       --params '{"debug": "no", "branch": "master"}' 2>&1 >> $LOG_FILE

echo -e "\n\n\n" >> $LOG_FILE
