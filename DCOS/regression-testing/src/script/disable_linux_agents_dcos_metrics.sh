#!/bin/bash

set -x
set -e
set -u
set -o pipefail

echo "Disabling dcos-metrics and dcos-checks-poststart on all the Linux agents"

SSH_KEY=${SSH_KEY:-"${OUTPUT}/id_rsa"}

VMSS_NAMES=$(az vmss list --resource-group ${RESOURCE_GROUP} | jq -r ".[] | select(.virtualMachineProfile.osProfile.linuxConfiguration != null) | .name")

PRIVATE_IPS=""
for VMSS_NAME in $VMSS_NAMES; do
  IPS=$(az vmss nic list --resource-group ${RESOURCE_GROUP} --vmss-name $VMSS_NAME | jq -r ".[] | .ipConfigurations[0].privateIpAddress")
  PRIVATE_IPS="$IPS $PRIVATE_IPS"
done
IPS="$PRIVATE_IPS"

if [[ -z $IPS ]]; then
  return 0
fi

declare -a cmds=(
  "sudo systemctl stop dcos-metrics-agent.service || echo skipped"
  "sudo systemctl stop dcos-metrics-agent.socket || echo skipped"
  "sudo systemctl disable dcos-metrics-agent.service || echo skipped"
  "sudo systemctl disable dcos-metrics-agent.socket || echo skipped"
  "sudo systemctl stop dcos-checks-poststart.timer || echo skipped"
  "sudo systemctl stop dcos-checks-poststart.service || echo skipped"
  "sudo systemctl disable dcos-checks-poststart.timer || echo skipped"
  "sudo systemctl disable dcos-checks-poststart.service || echo skipped")

scp -i ${SSH_KEY} -o ConnectTimeout=30 -o StrictHostKeyChecking=no -P 2200 ${SSH_KEY} azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com:/tmp/id_rsa

ssh_cmd="ssh -o ConnectTimeout=30 -o StrictHostKeyChecking=no"
for IP in $IPS; do
  for CMD in "${cmds[@]}"; do
    $ssh_cmd -i ${SSH_KEY} -p 2200 azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com "$ssh_cmd -i /tmp/id_rsa azureuser@$IP $CMD"
  done
done
echo "Successfully disabled dcos-metrics and dcos-checks-poststart on all the Linux agents"
