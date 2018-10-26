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

MESOS_SYSTEMD_DIR="/etc/systemd/system/dcos-mesos-slave-public.service.d"
mkdir -p $MESOS_SYSTEMD_DIR
echo "[Service]
Environment=MESOS_AUTHENTICATE_HTTP_READONLY=true
Environment=MESOS_AUTHENTICATE_HTTP_READWRITE=true
Environment=MESOS_HTTP_CREDENTIALS=/etc/ethos/dcos-mesos-agent-http-credentials
Environment=MESOS_CREDENTIAL=/etc/ethos/dcos-mesos-agent-secret" > $MESOS_SYSTEMD_DIR/10-dcos-mesos-agent-auth.conf
