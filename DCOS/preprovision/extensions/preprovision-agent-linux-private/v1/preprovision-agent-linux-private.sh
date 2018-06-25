#!/usr/bin/env bash

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

mkdir -p /etc/systemd/system/dcos-mesos-slave.service.d
echo "[Service]
Environment=MESOS_AUTHENTICATE_HTTP_READONLY=true
Environment=MESOS_AUTHENTICATE_HTTP_READWRITE=true
Environment=MESOS_HTTP_CREDENTIALS=/etc/ethos/dcos-mesos-agent-http-credentials
Environment=MESOS_CREDENTIAL=/etc/ethos/dcos-mesos-agent-secret" > /etc/systemd/system/dcos-mesos-slave.service.d/10-dcos-mesos-agent-auth.conf

mkdir -p /opt/azure/dcos
touch /opt/azure/dcos/postinstall.sh
chmod 744 /opt/azure/dcos/postinstall.sh
cat > /opt/azure/dcos/postinstall.sh << EOF
#!/bin/bash

source /opt/azure/containers/provision_source.sh

systemctl stop dcos-metrics-agent.socket
systemctl disable dcos-metrics-agent.socket
systemctl stop dcos-metrics-agent.service
systemctl disable dcos-metrics-agent.service

retrycmd_if_failure 10 10 120 curl -fsSL -o /opt/mesosphere/etc/dcos-diagnostics-runner-config.json https://dcos-mirror.azureedge.net/preprovision/dcos-diagnostics-runner-config-no-dcos-metrics.json

systemctl restart dcos-checks-poststart.service || echo skipped
EOF

