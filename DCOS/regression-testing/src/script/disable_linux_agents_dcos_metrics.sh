#!/bin/bash

set -x
set -e
set -u
set -o pipefail

echo "Disabling dcos-metrics on all the Linux agents"

SSH_KEY=${SSH_KEY:-"${OUTPUT}/id_rsa"}

VMSS_NAMES=$(az vmss list --resource-group ${RESOURCE_GROUP} | jq -r ".[] | select(.virtualMachineProfile.osProfile.linuxConfiguration != null) | .name")

PRIVATE_IPS=""
for VMSS_NAME in $VMSS_NAMES; do
  IPS=$(az vmss nic list --resource-group ${RESOURCE_GROUP} --vmss-name $VMSS_NAME | jq -r ".[] | .ipConfigurations[0].privateIpAddress")
  PRIVATE_IPS="$IPS $PRIVATE_IPS"
done
IPS="$PRIVATE_IPS"

if [[ -z $IPS ]]; then
  exit 0
fi

master_scp="scp -i ${SSH_KEY} -o ConnectTimeout=30 -o StrictHostKeyChecking=no -P 2200"
master_ssh="ssh -i ${SSH_KEY} -o ConnectTimeout=30 -o StrictHostKeyChecking=no -p 2200 azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com"
agent_ssh="ssh -i /tmp/id_rsa -o ConnectTimeout=30 -o StrictHostKeyChecking=no"

$master_scp ${SSH_KEY} azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com:/tmp/id_rsa

for IP in $IPS; do
  $master_ssh "$agent_ssh azureuser@$IP sudo systemctl stop dcos-metrics-agent.socket"
  $master_ssh "$agent_ssh azureuser@$IP sudo systemctl disable dcos-metrics-agent.socket"
  $master_ssh "$agent_ssh azureuser@$IP sudo systemctl stop dcos-metrics-agent.service"
  $master_ssh "$agent_ssh azureuser@$IP sudo systemctl disable dcos-metrics-agent.service"
  json=$($master_ssh "$agent_ssh azureuser@$IP cat /opt/mesosphere/etc/dcos-diagnostics-runner-config.json")
  tmpfile=$(mktemp)
  echo $json | jq 'del(.node_checks.checks.mesos_agent_registered_with_masters)' > $tmpfile
  $master_scp $tmpfile azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com:$tmpfile
  $master_ssh "scp -i /tmp/id_rsa -o ConnectTimeout=30 -o StrictHostKeyChecking=no $tmpfile azureuser@$IP:$tmpfile"
  $master_ssh "$agent_ssh azureuser@$IP sudo cp $tmpfile /opt/mesosphere/etc/dcos-diagnostics-runner-config.json"
  $master_ssh "$agent_ssh azureuser@$IP sudo systemctl restart dcos-checks-poststart.service || echo skipped"
  rm $tmpfile
done
echo "Successfully disabled dcos-metrics on all the Linux agents"
