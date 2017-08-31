#!/usr/bin/env bash
set -e

# Check if all parameters are set
if [[ -z $AZURE_USER ]]; then echo "ERROR: Parameter AZURE_USER is not set"; exit 1; fi
if [[ -z $AZURE_USER_PASSWORD ]]; then echo "ERROR: Parameter AZURE_USER_PASSWORD is not set"; exit 1; fi
if [[ -z $AZURE_REGION ]]; then echo "ERROR: Parameter AZURE_REGION is not set"; exit 1; fi
if [[ -z $AZURE_RESOURCE_GROUP ]]; then echo "ERROR: Parameter AZURE_RESOURCE_GROUP is not set"; exit 1; fi

if [[ -z $WINDOWS_SLAVES_COUNT ]]; then echo "ERROR: Parameter WINDOWS_SLAVES_COUNT is not set"; exit 1; fi
if [[ -z $WINDOWS_SLAVES_VM_SIZE ]]; then echo "ERROR: Parameter WINDOWS_SLAVES_VM_SIZE is not set"; exit 1; fi
if [[ -z $WINDOWS_SLAVES_PUBLIC_POOL_NAME ]]; then echo "ERROR: Parameter WINDOWS_SLAVES_PUBLIC_POOL_NAME is not set"; exit 1; fi
if [[ -z $WINDOWS_SLAVES_DNS_PREFIX ]]; then echo "ERROR: Parameter WINDOWS_SLAVES_DNS_PREFIX is not set"; exit 1; fi
if [[ -z $WINDOWS_SLAVES_ADMIN ]]; then echo "ERROR: Parameter WINDOWS_SLAVES_ADMIN is not set"; exit 1; fi
if [[ -z $WINDOWS_SLAVES_ADMIN_PASSWORD ]]; then echo "ERROR: Parameter WINDOWS_SLAVES_ADMIN_PASSWORD is not set"; exit 1; fi

if [[ -z $LINUX_MASTERS_COUNT ]]; then echo "ERROR: Parameter LINUX_MASTERS_COUNT is not set"; exit 1; fi
if [[ -z $LINUX_MASTERS_VM_SIZE ]]; then echo "ERROR: Parameter LINUX_MASTERS_VM_SIZE is not set"; exit 1; fi
if [[ -z $LINUX_MASTERS_DNS_PREFIX ]]; then echo "ERROR: Parameter LINUX_MASTERS_DNS_PREFIX is not set"; exit 1; fi
if [[ -z $LINUX_MASTERS_ADMIN ]]; then echo "ERROR: Parameter LINUX_MASTERS_ADMIN is not set"; exit 1; fi
if [[ -z $LINUX_MASTERS_PUBLIC_SSH_KEY ]]; then echo "ERROR: Parameter LINUX_MASTERS_PUBLIC_SSH_KEY is not set"; exit 1; fi

BASE_DIR=$(dirname $0)
TEMPLATES_DIR="$BASE_DIR/../../templates"


install_go_1_8() {
    which go > /dev/null && echo "Go is already installed" && return || echo "Installing Go 1.8"
    OUT_FILE="/tmp/go-1.8.tgz"
    GO_1_8_TGZ_URL="https://storage.googleapis.com/golang/go1.8.linux-amd64.tar.gz"
    wget $GO_1_8_TGZ_URL -O $OUT_FILE
    pushd $(dirname $OUT_FILE)
    tar xzf $OUT_FILE
    sudo mv go /usr/local
    popd
    rm -rf $OUT_FILE
    cat ~/.bashrc | grep -q '^export GOPATH=~/golang$' || (echo 'export GOPATH=~/golang' >> ~/.bashrc)
    cat ~/.bashrc | grep -q '^export PATH="\$PATH:/usr/local/go/bin:\$GOPATH/bin"$' || (echo 'export PATH="$PATH:/usr/local/go/bin:$GOPATH/bin"' >> ~/.bashrc)
    source ~/.bashrc
    mkdir -p $GOPATH
}

install_acs_engine_requirements() {
    sudo apt install git -y
    install_go_1_8
}

install_acs_engine_from_src() {
    which acs-engine > /dev/null && echo "ACS Engine is already installed" && return || echo "Installing ACS Engine from source"
    go get -v github.com/Azure/acs-engine
    cd $GOPATH/src/github.com/Azure/acs-engine
    git remote add dcos-windows https://github.com/yakman2020/acs-engine
    git pull -q dcos-windows brcampbe/windows-dcos --no-edit
    make bootstrap
    make build
    if [[ ! -e ~/bin ]]; then
        mkdir -p ~/bin
        PATH="$HOME/bin:$PATH"
    fi
    cp $GOPATH/src/github.com/Azure/acs-engine/bin/acs-engine ~/bin/
}

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


# 1. Install ACS Engine from the 'dcos-windows' branch and Azure CLI 2.0
install_acs_engine_requirements
install_acs_engine_from_src
install_azure_cli_2


# 2. Generate the Azure ARM deploy files
ACS_TEMPLATE="$TEMPLATES_DIR/dcos/acs-engine.json"
ACS_RENDERED_TEMPLATE="/tmp/dcos-acs-engine.json"
DCOS_DEPLOY_DIR="/tmp/dcos-windows-deploy-dir"
eval "cat << EOF
$(cat $ACS_TEMPLATE)
EOF
" > $ACS_RENDERED_TEMPLATE
rm -rf $DCOS_DEPLOY_DIR
acs-engine generate --output-directory $DCOS_DEPLOY_DIR $ACS_RENDERED_TEMPLATE
rm -rf $BASE_DIR/translations # Left-over after running 'acs-engine generate'
rm $ACS_RENDERED_TEMPLATE


# 3. Deploy the DCOS with Mesos environment
DEPLOY_TEMPLATE_FILE="$DCOS_DEPLOY_DIR/azuredeploy.json"
DEPLOY_PARAMS_FILE="$DCOS_DEPLOY_DIR/azuredeploy.parameters.json"
azure_cli_login
az group create -l "$AZURE_REGION" -n "$AZURE_RESOURCE_GROUP"
echo "Started the DCOS deployment"
az group deployment create -g "$AZURE_RESOURCE_GROUP" --template-file $DEPLOY_TEMPLATE_FILE --parameters @$DEPLOY_PARAMS_FILE
rm -rf $DCOS_DEPLOY_DIR


# 4. Enable WinRM on the Windows slaves
WINDOWS_SLAVES=$(az vm list --resource-group $AZURE_RESOURCE_GROUP --output table | grep -v "^dcos-master-" | sed 1,2d | awk '{print $1}')
for VM in $WINDOWS_SLAVES; do
    echo "Enabling WinRM on Windows slave: $VM"
    az vm extension set --resource-group $AZURE_RESOURCE_GROUP \
                        --vm-name $VM \
                        --name CustomScriptExtension \
                        --publisher Microsoft.Compute \
                        --settings $TEMPLATES_DIR/enable-winrm.json
done