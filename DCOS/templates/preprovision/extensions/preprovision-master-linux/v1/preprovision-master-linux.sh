#!/bin/bash
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

mkdir -p /etc/systemd/system/dcos-marathon.service.d
echo "[Service]
Environment=MESOSPHERE_HTTP_CREDENTIALS=frameworkuser:frameworkpassword" > /etc/systemd/system/dcos-marathon.service.d/10-dcos-marathon-authentication.conf
