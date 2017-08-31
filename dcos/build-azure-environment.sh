#!/usr/bin/env bash
set -e

# Check if all parameters are set
if [[ -z $AZURE_USER ]]; then echo "ERROR: Parameter AZURE_USER is not set"; exit 1; fi
if [[ -z $AZURE_USER_PASSWORD ]]; then echo "ERROR: Parameter AZURE_USER_PASSWORD is not set"; exit 1; fi
if [[ -z $AZURE_REGION ]]; then echo "ERROR: Parameter AZURE_REGION is not set"; exit 1; fi
if [[ -z $AZURE_RESOURCE_GROUP ]]; then echo "ERROR: Parameter AZURE_RESOURCE_GROUP is not set"; exit 1; fi

if [[ -z $WINDOWS_SLAVE_VM_SIZE ]]; then echo "ERROR: Parameter WINDOWS_SLAVE_VM_SIZE is not set"; exit 1; fi
if [[ -z $WINDOWS_SLAVE_DNS_PREFIX ]]; then echo "ERROR: Parameter WINDOWS_SLAVE_DNS_PREFIX is not set"; exit 1; fi
if [[ -z $WINDOWS_SLAVE_ADMIN ]]; then echo "ERROR: Parameter WINDOWS_SLAVE_ADMIN is not set"; exit 1; fi
if [[ -z $WINDOWS_SLAVE_ADMIN_PASSWORD ]]; then echo "ERROR: Parameter WINDOWS_SLAVE_ADMIN_PASSWORD is not set"; exit 1; fi

if [[ -z $LINUX_MASTER_VM_SIZE ]]; then echo "ERROR: Parameter LINUX_MASTER_VM_SIZE is not set"; exit 1; fi
if [[ -z $LINUX_MASTER_DNS_PREFIX ]]; then echo "ERROR: Parameter LINUX_MASTER_DNS_PREFIX is not set"; exit 1; fi
if [[ -z $LINUX_MASTER_ADMIN ]]; then echo "ERROR: Parameter LINUX_MASTER_ADMIN is not set"; exit 1; fi
if [[ -z $LINUX_MASTER_PUBLIC_SSH_KEY ]]; then echo "ERROR: Parameter LINUX_MASTER_PUBLIC_SSH_KEY is not set"; exit 1; fi

BASE_DIR=$(dirname $0)
TEMPLATES_DIR="$BASE_DIR/../templates"

install_azure_cli_2() {
    which az > /dev/null && echo "Azure CLI is already installed" && return || echo "Installing Azure CLI"
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ wheezy main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
    sudo apt-key adv --keyserver packages.microsoft.com --recv-keys 417A0893
    sudo apt-get install apt-transport-https
    sudo apt-get update && sudo apt-get install azure-cli
}

azure_cli_login() {
    az account list --output json | grep -q "\"name\": \"$AZURE_USER\",$" && echo "Account is already logged" && return || echo "Logging with the user: $AZURE_USER"
    az login -u $AZURE_USER -p $AZURE_USER_PASSWORD
}


# 1. Install the Azure CLI 2.0
install_azure_cli_2


# 2. Deploy the DCOS with Mesos environment
DEPLOY_FILE="$TEMPLATES_DIR/dcos/azuredeploy.json"
DEPLOY_PARAMS_TEMPLATE_FILE="$TEMPLATES_DIR/dcos/azuredeploy.parameters.json"
azure_cli_login
az group create -l "$AZURE_REGION" -n "$AZURE_RESOURCE_GROUP"
echo "Started the DCOS deployment"
DEPLOY_PARAMS_FILE=$(mktemp)
eval "cat << EOF
$(cat $DEPLOY_PARAMS_TEMPLATE_FILE)
EOF
" > $DEPLOY_PARAMS_FILE
az group deployment create -g "$AZURE_RESOURCE_GROUP" --template-file $DEPLOY_FILE --parameters @$DEPLOY_PARAMS_FILE
rm $DEPLOY_PARAMS_FILE
