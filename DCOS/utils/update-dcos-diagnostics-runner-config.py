#!/usr/bin/env python3

import json
import sys

config_file = '/opt/mesosphere/etc/dcos-diagnostics-runner-config.json'
with open(config_file, 'r') as f:
    config_str = f.read()

config_json = json.loads(config_str)
config_json['node_checks']['checks'].pop('mesos_agent_registered_with_masters')

print(json.dumps(config_json, indent=2))
