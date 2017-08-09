#!/bin/bash

basedir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

set -e

resource_group="dcos_mesos_${commitid}"
template_path="$basedir/../AzureTemplate"
deploy_template_file="$template_path/azuredeploy.json"
deploy_param_file="$template_path/azuredeploy.parameters.json"
#master_vm_name="master-${commitid}0"
#agent_vm_name="agent-${commitid}0"
agent_dns_prefix="dcosagentpre"
master_dns_prefix="dcosmasterpre"
render_params=$(mktemp)

# Login to Azure
az login -u ${az_user} -p ${az_password}

# Create new resource group
az group create -l ${azure_region} -n $resource_group

# Render parameters file with current variables
eval "cat <<EOF
$(<${deploy_param_file})
EOF
" >> $render_params

# Deploy the env into Azure
az group deployment create -g $resource_group --template-file $deploy_template_file --parameters @${render_params}

# Get Master and Agent VM names
master_vm_name=$(az vm list --resource-group $resource_group --output table | grep "master" | awk '{ print $1 }')
agent_vm_name=$(az vm list --resource-group $resource_group --output table | grep "win-ag" | awk '{ print $1 }')

# Get Private and Public IP addresses
echo "Getting mesos master IP addresses"
master_private_ip=$(az vm list-ip-addresses --name $master_vm_name --output table | grep "$master_vm_name"  | awk '{ print $3 }')
echo "Private IP Address for master Mesos is : $master_private_ip"
#master_public_ip = $(az vm list-ip-addresses --name $master_vm_name --output table | grep "$master_vm_name"  | awk '{ print $2 }')
master_public_ip=$(az network public-ip list --resource-group $resource_group --output table | grep "$master_dns_prefix" | awk '{ print $2 }')
echo "Public IP Address for master Mesos is: $master_public_ip"
echo "Getting mesos agent IP addresses"
agent_private_ip=$(az vm list-ip-addresses --name $agent_vm_name --output table | grep "$agent_vm_name"  | awk '{ print $3 }')
echo "Private IP Address for agent Mesos is: $agent_private_ip"
#agent_public_ip = $(az vm list-ip-addresses --name $agent_vm_name --output table | grep "$agent_vm_name"  | awk '{ print $2 }')
agent_public_ip=$(az network public-ip list --resource-group $resource_group --output table | grep "$agent_dns_prefix" | awk '{ print $2 }')
echo "Public IP Address for agent Mesos is: $agent_public_ip"

# Enable WinRM on windows node
az vm extension set --resource-group $resource_group --vm-name $agent_vm_name --name CustomScriptExtension --publisher Microsoft.Compute --settings $basedir/../AzureTemplate/enable-winrm.json

# Install agent
az vm extension set --resource-group $resource_group --vm-name $agent_vm_name --name CustomScriptExtension --publisher Microsoft.Compute --settings $basedir/../AzureTemplate/install-agent.json

# Start mesos agent on windows agent node
python /home/ubuntu/ci-tools/wsman.py -U https://${agent_public_ip}:5986/wsman -u $az_user -p $az_password 'powershell -ExecutionPolicy RemoteSigned C:\mesos-jenkins\DCOS\start-mesos-agent.ps1 -master_ip $master_private_ip -agent_ip $agent_private_ip'
