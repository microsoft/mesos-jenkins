#!/bin/bash

basedir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

set -e

resource_group="dcos_mesos_${commitid}"
template_file="$basedir/../AzureTemplate/azuredeploy.json"
param_file="$basedir/../AzureTemplate/azuredeploy.parameters.json"
master_vm_name="master-${commitid}0"
agent_vm_name="agent-${commitid}0"
render_params=$(mktemp)

# Login to Azure
az login -u ${az_user} -p ${az_password}

# Create new resource group
az group create -l ${azure_region} -n $resource_group

# Render parameters file with current variables
eval "cat <<EOF
$(<$param_file)
EOF
" >> $render_params

# Deploy the env into Azure
az group deployment create -g $resource_group --template-file $template_file --parameters @${render_params}

# Get Private and Public IP addresses
echo "Getting mesos master IP addresses"
master_private_ip = $(az vm list-ip-addresses --name $master_vm_name --output table | grep "$master_vm_name"  | awk '{ print $3 }')
echo "Private IP Address for master Mesos is : $master_private_ip"
master_public_ip = $(az vm list-ip-addresses --name $master_vm_name --output table | grep "$master_vm_name"  | awk '{ print $2 }')
echo "Public IP Address for master Mesos is: $master_public_ip"
echo "Getting mesos agent IP addresses"
agent_private_ip = $(az vm list-ip-addresses --name $agent_vm_name --output table | grep "$agent_vm_name"  | awk '{ print $3 }')
echo "Private IP Address for agent Mesos is: $agent_private_ip"
agent_public_ip = $(az vm list-ip-addresses --name $agent_vm_name --output table | grep "$agent_vm_name"  | awk '{ print $2 }')
echo "Public IP Address for agent Mesos is: $agent_public_ip"

# Start mesos agent on windows agent node
python /home/ubuntu/ci-tools/wsman.py -U https://$agent_public_ip:5986/wsman -u $az_user -p $az_password 'powershell -ExecutionPolicy RemoteSigned C:\mesos-jenkins\DCOS\start-mesos-agent.ps1 -master_ip $master_private_ip -agent_ip $agent_private_ip'
