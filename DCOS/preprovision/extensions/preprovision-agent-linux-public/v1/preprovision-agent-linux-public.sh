#!/usr/bin/env bash
set -e

mkdir -p /etc/ethos/
touch /etc/ethos/dcos-mesos-agent-secret
chmod 600 /etc/ethos/dcos-mesos-agent-secret
cat > /etc/ethos/dcos-mesos-agent-secret << EOF
{
  "principal": "mycred1",
  "secret": "mysecret1"
}
EOF

touch /etc/ethos/dcos-mesos-agent-http-credentials
chmod 600 /etc/ethos/dcos-mesos-agent-http-credentials
cat > /etc/ethos/dcos-mesos-agent-http-credentials << EOF
{
  "credentials": [
    {
      "principal": "mycred2",
      "secret": "mysecret2"
    }
  ]
}
EOF

mkdir -p /etc/systemd/system/dcos-mesos-slave-public.service.d
echo "[Service]
Environment=MESOS_AUTHENTICATE_HTTP_READONLY=true
Environment=MESOS_AUTHENTICATE_HTTP_READWRITE=true
Environment=MESOS_HTTP_CREDENTIALS=/etc/ethos/dcos-mesos-agent-http-credentials
Environment=MESOS_CREDENTIAL=/etc/ethos/dcos-mesos-agent-secret" > /etc/systemd/system/dcos-mesos-slave-public.service.d/10-dcos-mesos-agent-public-auth.conf

mkdir -p /opt/azure/dcos

UPDATE_CONFIG_SCRIPT="/opt/azure/dcos/update-dcos-checks-config.py"
touch $UPDATE_CONFIG_SCRIPT
chmod +x $UPDATE_CONFIG_SCRIPT
cat > $UPDATE_CONFIG_SCRIPT << EOF
#!/usr/env/bin python
import json
import sys

CONFIG_FILE = sys.argv[1]

with open(CONFIG_FILE, 'r') as f:
    str_config = f.read()

config = json.loads(str_config)
config['node_checks']['checks'].pop('mesos_agent_registered_with_masters')
config['node_checks']['poststart'].remove('mesos_agent_registered_with_masters')

with open(CONFIG_FILE, 'w') as f:
    f.write(json.dumps(config, sort_keys=True, indent=2))
EOF

touch /opt/azure/dcos/postinstall.sh
chmod 744 /opt/azure/dcos/postinstall.sh
cat > /opt/azure/dcos/postinstall.sh << EOF
#!/bin/bash

source /opt/azure/containers/provision_source.sh

systemctl stop dcos-metrics-agent.socket
systemctl disable dcos-metrics-agent.socket
systemctl stop dcos-metrics-agent.service
systemctl disable dcos-metrics-agent.service

if [[ -e "/opt/mesosphere/etc/dcos-check-config.json" ]]; then
    python $UPDATE_CONFIG_SCRIPT "/opt/mesosphere/etc/dcos-check-config.json"
elif [[ -e "/opt/mesosphere/etc/dcos-diagnostics-runner-config.json" ]]; then
    python $UPDATE_CONFIG_SCRIPT "/opt/mesosphere/etc/dcos-diagnostics-runner-config.json"
fi

echo "Waiting for reachable ZooKeeper DNS addresses: zk-1.zk, zk-2.zk, zk-3.zk, zk-4.zk and zk-5.zk"
TIMEOUT=600
SECONDS=0
while true; do
    if [[ \$SECONDS -gt \$TIMEOUT ]]; then
        echo "ZooKeeper DNS addresses didn't become reachable within the allowed timeout of \$TIMEOUT seconds"
        exit 1
    fi
    if \$(ping -c1 zk-1.zk &>/dev/null && ping -c1 zk-2.zk &>/dev/null && ping -c1 zk-3.zk &>/dev/null && ping -c1 zk-4.zk &>/dev/null && ping -c1 zk-5.zk &>/dev/null); then
        echo "ZooKeeper DNS addresses are functional"
        break
    fi
    sleep 1
done

# The /var/lib/dcos/cluster-id file is needed by dcos-telegraf and this
# is generated by the dcos-metrics bootstrapper
source /opt/mesosphere/environment
source /opt/mesosphere/etc/dcos-metrics.env
export PYTHONPATH=/opt/mesosphere/lib/python3.6/site-packages
/opt/mesosphere/bin/bootstrap dcos-metrics-agent
systemctl restart dcos-telegraf

systemctl restart dcos-checks-poststart.service
EOF
