#!/usr/bin/env bash
set -e

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

systemctl stop dcos-metrics-agent.socket
systemctl disable dcos-metrics-agent.socket
systemctl stop dcos-metrics-agent.service
systemctl disable dcos-metrics-agent.service

if [[ -e "/opt/mesosphere/etc/dcos-check-config.json" ]]; then
    python $UPDATE_CONFIG_SCRIPT "/opt/mesosphere/etc/dcos-check-config.json"
elif [[ -e "/opt/mesosphere/etc/dcos-diagnostics-runner-config.json" ]]; then
    python $UPDATE_CONFIG_SCRIPT "/opt/mesosphere/etc/dcos-diagnostics-runner-config.json"
fi

systemctl restart dcos-checks-poststart.service
