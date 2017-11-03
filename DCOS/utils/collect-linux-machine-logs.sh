#!/usr/bin/env bash
set -e

if [[ $# -ne 1 ]]; then
    echo "USAGE: $0 <tmp_logs_dir>"
    exit 1
fi

TMP_LOGS_DIR="$1"

rm -rf $TMP_LOGS_DIR && mkdir -p $TMP_LOGS_DIR/logs

systemctl list-units dcos*service --all > $TMP_LOGS_DIR/systemd-dcos-services.txt
for SERVICE_NAME in $(ls /etc/systemd/system/dcos.target.wants | grep 'dcos-.*\.service'); do
    sudo journalctl -u $SERVICE_NAME -a --no-tail > $TMP_LOGS_DIR/logs/${SERVICE_NAME}.log
done
