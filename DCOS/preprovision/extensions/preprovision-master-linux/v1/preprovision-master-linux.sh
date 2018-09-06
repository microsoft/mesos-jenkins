#!/usr/bin/env bash
set -e

[[ -e /usr/bin/chmod ]] || ln -s /bin/chmod /usr/bin/chmod
[[ -e /usr/bin/chown ]] || ln -s /bin/chown /usr/bin/chown

mkdir -p /etc/ethos/
touch /etc/ethos/dcos-mesos-master-secrets
chmod 600 /etc/ethos/dcos-mesos-master-secrets
cat > /etc/ethos/dcos-mesos-master-secrets << EOF
{
  "credentials": [
    {
      "principal": "mycred1",
      "secret": "mysecret1"
    }
  ]
}
EOF

mkdir -p /etc/systemd/system/dcos-mesos-master.service.d
echo "[Service]
Environment=MESOS_CREDENTIALS=/etc/ethos/dcos-mesos-master-secrets
Environment=MESOS_AUTHENTICATE_AGENTS=true" > /etc/systemd/system/dcos-mesos-master.service.d/10-dcos-mesos-authentication.conf

