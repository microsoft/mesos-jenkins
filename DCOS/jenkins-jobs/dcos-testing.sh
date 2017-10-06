#!/usr/bin/env bash
set -e

export BUILD_ID=$(date +%m%d%y%T | sed 's|\:||g')
export AZURE_RESOURCE_GROUP="dcos_testing_${BUILD_ID}"
export LINUX_MASTER_DNS_PREFIX="dcos-testing-lin-master-${BUILD_ID}"
export LINUX_ADMIN="azureuser"
export WIN_AGENT_PUBLIC_POOL="winpubpool"
export WIN_AGENT_DNS_PREFIX="dcos-testing-win-agent-${BUILD_ID}"
export WIN_AGENT_ADMIN="azureuser"
if [[ -z $LINUX_PUBLIC_SSH_KEY ]]; then
    PUB_KEY_FILE="$HOME/.ssh/id_rsa.pub"
    if [[ ! -e $PUB_KEY_FILE ]]; then
        echo "ERROR: LINUX_PUBLIC_SSH_KEY was not set and the default $PUB_KEY_FILE doesn't exist"
        exit 1
    fi
    export LINUX_PUBLIC_SSH_KEY=$(cat $PUB_KEY_FILE)
fi
if [[ -z $AZURE_REGION ]]; then
    echo "ERROR: Parameter AZURE_REGION is not set"
    exit 1
fi
if [[ $(echo "$AZURE_REGION" | grep "\s") ]]; then
    echo "ERROR: The AZURE_REGION parameter must not contain any spaces"
fi

if [[ "$DCOS_DEPLOYMENT_TYPE" != "simple" ]]; then
    echo "ERROR: Only simple deployment type is supported for now in the Jenkins job. DCOS_DEPLOYMENT_TYPE is set to: $DCOS_DEPLOYMENT_TYPE"
    exit 1
fi

DIR=$(dirname $0)
MASTER_PUBLIC_ADDRESS="${LINUX_MASTER_DNS_PREFIX}.${AZURE_REGION}.cloudapp.azure.com"
WIN_AGENT_PUBLIC_ADDRESS="${WIN_AGENT_DNS_PREFIX}.${AZURE_REGION}.cloudapp.azure.com"
IIS_HEALTH_CHECK_TEMPLATE_URL="${DCOS_WINDOWS_BOOTSTRAP_URL}/iis-health-checks.json"
LOG_SERVER_ADDRESS="10.3.1.6"
LOG_SERVER_USER="logs"
REMOTE_LOGS_DIR="/data/dcos-testing"


job_cleanup() {
    echo "Cleanup in progress for the current Azure DCOS deployment"
    az group delete --yes --name $AZURE_RESOURCE_GROUP --output table
    echo "Finished the environment cleanup"
}

handle_command_error() {
    ERROR_MESSAGE="$1"
    COLLECT_LOGS="$2"
    echo $ERROR_MESSAGE
    if [[ "$COLLECT_LOGS" = "True" ]]; then
        collect_logs "$MASTER_PUBLIC_ADDRESS" "$WIN_AGENT_PUBLIC_ADDRESS"
    fi
    job_cleanup
    exit 1
}

check_open_port() {
    set +e
    ADDRESS="$1"
    PORT="$2"
    TIMEOUT=120
    echo "Checking, with a timeout of $TIMEOUT seconds, if the port $PORT is open at the address: $ADDRESS"
    nc -z "$ADDRESS" "$PORT" -w $TIMEOUT
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Port $PORT is not open at the address: $ADDRESS"
        return 1
    fi
    set -e
}

open_dcos_port() {
    echo "Opening DCOS port: 80"
    MASTER_LB_NAME=$(az network lb list --resource-group $AZURE_RESOURCE_GROUP --output table | grep 'dcos-master' | awk '{print $2}')
    MASTER_NIC_NAME=$(az network nic list --resource-group $AZURE_RESOURCE_GROUP --output table | grep 'dcos-master' | awk '{print $3}')
    NAT_RULE_NAME="DCOS_Port_80"
    az network lb inbound-nat-rule create --resource-group $AZURE_RESOURCE_GROUP --lb-name $MASTER_LB_NAME \
                                          --name $NAT_RULE_NAME --protocol Tcp --frontend-port 80 --backend-port 80 --output table
    az network nic ip-config inbound-nat-rule add --resource-group $AZURE_RESOURCE_GROUP --lb-name $MASTER_LB_NAME --nic-name $MASTER_NIC_NAME \
                                                  --inbound-nat-rule $NAT_RULE_NAME --ip-config-name ipConfigNode --output table
    MASTER_SG_NAME=$(az network nsg list --resource-group $AZURE_RESOURCE_GROUP --output table | grep 'dcos-master' | awk '{print $2}')
    az network nsg rule create --resource-group $AZURE_RESOURCE_GROUP --nsg-name $MASTER_SG_NAME --name $NAT_RULE_NAME \
                               --access Allow --protocol Tcp --direction Inbound --priority 100 --destination-port-range 80 --output table
    check_open_port "$MASTER_PUBLIC_ADDRESS" "80"
}

deploy_iis_with_health_checks() {
    echo "Deploying the IIS marathon template on DCOS"
    dcos marathon app add $IIS_HEALTH_CHECK_TEMPLATE_URL
    TASK_ID=$(dcos marathon task list | grep 'dcos-iis' | awk '{print $5}')
    COUNT=0
    while [[ -z $TASK_ID ]]; do
        if [[ $COUNT -eq 5 ]]; then
            echo "ERROR: IIS was deployed, but there wasn't any task launched by marathon within a $(($COUNT * 3)) seconds timeout"
            return 1
        fi
        echo "Trying to get the IIS task ID"
        sleep 3
        TASK_ID=$(dcos marathon task list | grep 'dcos-iis' | awk '{print $5}')
        COUNT=$(($COUNT + 1))
    done
    COUNT=0
    STATE=$(dcos marathon task show $TASK_ID | python -c "import sys, json; data = json.load(sys.stdin); print(data['state'])")
    while [[ "$STATE" != "TASK_RUNNING" ]]; do
        if [[ $COUNT -eq 30 ]]; then
            echo "ERROR: IIS task didn't reach RUNNING state within a $(($COUNT * 60)) seconds timeout"
            return 1
        fi
        echo "Waiting for IIS task to be RUNNING"
        sleep 60
        COUNT=$(($COUNT + 1))
        TASK_ID=$(dcos marathon task list | grep 'dcos-iis' | awk '{print $5}')
        STATE=$(dcos marathon task show $TASK_ID | python -c "import sys, json; data = json.load(sys.stdin); print(data['state'])")
    done
    COUNT=0
    HAS_HEALTHCHECKS=$(dcos marathon task show $TASK_ID | python -c "import sys, json; data = json.load(sys.stdin); print(('healthCheckResults' in data.keys()))")
    while [[ "$HAS_HEALTHCHECKS" != "True" ]]; do
        if [[ $COUNT -eq 10 ]]; then
            echo "ERROR: Couldn't read IIS task health checks within a $(($COUNT * 6)) seconds"
            return 1
        fi
        echo "Trying to get IIS task health check results"
        sleep 6
        COUNT=$(($COUNT + 1))
        HAS_HEALTHCHECKS=$(dcos marathon task show $TASK_ID | python -c "import sys, json; data = json.load(sys.stdin); print(('healthCheckResults' in data.keys()))")
    done
    COUNT=0
    IS_ALIVE=$(dcos marathon task show $TASK_ID | python -c "import sys, json; data = json.load(sys.stdin); print(data['healthCheckResults'][0]['alive'])")
    if [[ "$IS_ALIVE" != "True" ]]; then
        echo "ERROR: IIS task health checks didn't report successfully"
        return 1
    fi
    check_open_port "$WIN_AGENT_PUBLIC_ADDRESS" "80"
    echo "IIS successfully deployed on DCOS"
}

run_functional_tests() {
    MASTER_ADDRESS="$1"
    dcos config set core.dcos_url "http://${MASTER_ADDRESS}:80"
    deploy_iis_with_health_checks
}

run_ssh_command() {
    ADDRESS="$1"
    CMD="$2"
    ssh -o 'PasswordAuthentication=no' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' azureuser@$ADDRESS "$CMD"
}

download_files_via_scp() {
    ADDRESS="$1"
    REMOTE_PATH="$2"
    LOCAL_PATH="$3"
    scp -r -o 'PasswordAuthentication=no' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' azureuser@$ADDRESS:$REMOTE_PATH $LOCAL_PATH
}

mount_windows_share() {
    local HOST=$1
    local USER=$2
    local PASS=$3
    sudo mkdir -p /mnt/$HOST
    sudo mount -t cifs //$HOST/C$ /mnt/$HOST -o username=$USER,password=$PASS,vers=3.0
}

umount_windows_share(){
    local HOST=$1
    sudo umount /mnt/$HOST
    sudo rmdir /mnt/$HOST
}

collect_logs() {
    echo "Collecting logs from the DCOS nodes"
    # Collect logs from the Linux master node
    echo "Collecting Linux master logs"
    MASTER_LOGS_DIR="/tmp/linux_master"
    run_ssh_command $MASTER_PUBLIC_ADDRESS "rm -rf $MASTER_LOGS_DIR ; mkdir -p $MASTER_LOGS_DIR/logs"
    run_ssh_command $MASTER_PUBLIC_ADDRESS "systemctl list-units dcos*service --all > $MASTER_LOGS_DIR/systemd-dcos-services.txt"
    run_ssh_command $MASTER_PUBLIC_ADDRESS "for i in \$(cat $MASTER_LOGS_DIR/systemd-dcos-services.txt | grep '^dcos-' | awk '{print \$1}' | cut -d '.' -f1); do sudo journalctl -u \$i -a --no-tail > $MASTER_LOGS_DIR/logs/\$i.log ; done"
    LOGS_DIR="/tmp/dcos-logs/$BUILD_ID"
    rm -rf $LOGS_DIR && mkdir -p $LOGS_DIR
    download_files_via_scp $MASTER_PUBLIC_ADDRESS "$MASTER_LOGS_DIR" "$LOGS_DIR"
    # Collect logs from the Windows node
    echo "Collecting Windows agent logs"
    mount_windows_share $WIN_AGENT_PUBLIC_ADDRESS $WIN_AGENT_ADMIN $WIN_AGENT_ADMIN_PASSWORD
    mkdir -p "$LOGS_DIR/windows_agent"
    cp -rf /mnt/$WIN_AGENT_PUBLIC_ADDRESS/mesos/log "$LOGS_DIR/windows_agent/logs"
    umount_windows_share $WIN_AGENT_PUBLIC_ADDRESS
    # Upload logs to log server
    scp -o 'PasswordAuthentication=no' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -r $LOGS_DIR $LOG_SERVER_USER@$LOG_SERVER_ADDRESS:"${REMOTE_LOGS_DIR}/"
}

# Deploy DCOS master + slave nodes
$DIR/../acs-engine-dcos-deploy.sh || handle_command_error "ERROR: Failed to deploy DCOS on Azure" "False"
echo "Linux master public address: $MASTER_PUBLIC_ADDRESS"
echo "Windows agent public address: $WIN_AGENT_PUBLIC_ADDRESS"

# Open DCOS API & GUI port
open_dcos_port || handle_command_error "ERROR: Failed to open the DCOS port" "True"

# Deploy a simple IIS on DCOS via the CLI and wait for it to finish its health checks
run_functional_tests "$MASTER_PUBLIC_ADDRESS" || handle_command_error "ERROR: Failed to run functional tests" "True"

# Collect any the logs and do the the final cleanup
collect_logs "$MASTER_PUBLIC_ADDRESS" "$WIN_AGENT_PUBLIC_ADDRESS"
job_cleanup

echo "Successfully tested an Azure DCOS deployment with the latest Mesos binaries"
