#!/usr/bin/env bash
set -e

export BUILD_ID=$(date +%m%d%y%T | sed 's|\:||g')
export AZURE_RESOURCE_GROUP="dcos_testing_${BUILD_ID}"
export LINUX_ADMIN="azureuser"
export WIN_AGENT_PUBLIC_POOL="winpubpool"
export WIN_AGENT_PRIVATE_POOL="winpripool"
export LINUX_AGENT_PUBLIC_POOL="linpubpool"
export LINUX_AGENT_PRIVATE_POOL="linpripool"
export LINUX_MASTER_DNS_PREFIX="dcos-testing-lin-master-${BUILD_ID}"
export WIN_AGENT_DNS_PREFIX="dcos-testing-win-agent-${BUILD_ID}"
export LINUX_AGENT_DNS_PREFIX="dcos-testing-lin-agent-${BUILD_ID}"
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

if [[ "$DCOS_DEPLOYMENT_TYPE" = "simple" ]]; then
    export LINUX_MASTER_COUNT="1"
    export LINUX_PUBLIC_AGENT_COUNT="0"
    export LINUX_PRIVATE_AGENT_COUNT="0"
    export WIN_PUBLIC_AGENT_COUNT="1"
    export WIN_PRIVATE_AGENT_COUNT="0"
elif [[ "$DCOS_DEPLOYMENT_TYPE" = "hybrid" ]]; then
    export LINUX_MASTER_COUNT="3"
    export LINUX_PUBLIC_AGENT_COUNT="1"
    export LINUX_PRIVATE_AGENT_COUNT="1"
    export WIN_PUBLIC_AGENT_COUNT="1"
    export WIN_PRIVATE_AGENT_COUNT="1"
else
    echo "ERROR: $DCOS_DEPLOYMENT_TYPE DCOS_DEPLOYMENT_TYPE is not supported"
    exit 1
fi

DIR=$(dirname $0)
MASTER_PUBLIC_ADDRESS="${LINUX_MASTER_DNS_PREFIX}.${AZURE_REGION}.cloudapp.azure.com"
WIN_AGENT_PUBLIC_ADDRESS="${WIN_AGENT_DNS_PREFIX}.${AZURE_REGION}.cloudapp.azure.com"
LINUX_AGENT_PUBLIC_ADDRESS="${LINUX_AGENT_DNS_PREFIX}.${AZURE_REGION}.cloudapp.azure.com"
IIS_HEALTH_CHECK_TEMPLATE_URL="${DCOS_WINDOWS_BOOTSTRAP_URL}/iis-health-checks.json"
LOG_SERVER_ADDRESS="10.3.1.6"
LOG_SERVER_USER="logs"
REMOTE_LOGS_DIR="/data/dcos-testing"
UTILS_FILE="$DIR/../utils/utils.sh"

. $UTILS_FILE


job_cleanup() {
    #
    # Deletes the Azure resource group used for the deployment
    #
    echo "Cleanup in progress for the current Azure DCOS deployment"
    az group delete --yes --name $AZURE_RESOURCE_GROUP --output table
    echo "Finished the environment cleanup"
}

handle_command_error() {
    #
    # - Prints the error message given as the first parameter
    # - If the second parameter is "True", it does a collect logs for whole deployment
    # - Does the job cleanup
    #
    local ERROR_MESSAGE="$1"
    local COLLECT_LOGS="$2"
    echo $ERROR_MESSAGE
    if [[ "$COLLECT_LOGS" = "True" ]]; then
        collect_logs || echo "ERROR: Failed to collect logs"
    fi
    job_cleanup
    exit 1
}

check_open_port() {
    #
    # Checks with a timeout of 120 seconds if a particular port (TCP or UDP) is open (nc tool is used for this)
    #
    set +e
    which nc > /dev/null
    if [[ $? -ne 0 ]]; then
        echo "ERROR: nc tool is not installed"
        return 1
    fi
    local ADDRESS="$1"
    local PORT="$2"
    local TIMEOUT=120
    echo "Checking, with a timeout of $TIMEOUT seconds, if the port $PORT is open at the address: $ADDRESS"
    nc -z "$ADDRESS" "$PORT" -w $TIMEOUT
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Port $PORT is not open at the address: $ADDRESS"
        return 1
    fi
    set -e
}

open_dcos_port() {
    #
    # This function opens the GUI endpoint on the first master unit
    #
    echo "Opening DCOS port: 80"
    MASTER_LB_NAME=$(az network lb list --resource-group $AZURE_RESOURCE_GROUP --output table | grep 'dcos-master' | awk '{print $2}')
    MASTER_NIC_NAME=$(az network nic list --resource-group $AZURE_RESOURCE_GROUP --output table | grep 'dcos-master' | awk '{print $3}' | head -1) # NOTE: Take the fist master NIC
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
    #
    # - Deploys an IIS app via marathon
    # - Checks if marathon successfully launched a Mesos task
    # - Waits for the health checks successful report
    # - Checks if the IIS exposed public port 80 is open
    #
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
    #
    # Run the following DCOS functional tests:
    #  - Deploy an IIS with health checks
    #
    dcos config set core.dcos_url "http://${MASTER_PUBLIC_ADDRESS}:80"
    deploy_iis_with_health_checks
}

get_private_addresses_for_linux_public_agents() {
    #
    # Returns the private addresses for the Linux Public Mesos agents
    #
    NODE_IDS=$(dcos node --json | python -c "import json, sys ; d = json.load(sys.stdin) ; v = [s['id'] for s in d if s['attributes']['os'] == 'linux' and 'public_ip' in s['attributes'].keys() and  s['attributes']['public_ip'] == 'yes'] ; print('\n'.join(v))")
    for ID in $NODE_IDS; do
        dcos node | grep $ID | awk '{print $2}'
    done
}

get_private_addresses_for_linux_private_agents() {
    #
    # Returns the private addresses for the Linux Private Mesos agents
    #
    NODE_IDS=$(dcos node --json | python -c "import json, sys ; d = json.load(sys.stdin) ; v = [s['id'] for s in d if s['attributes']['os'] == 'linux' and 'public_ip' not in s['attributes'].keys()] ; print('\n'.join(v))")
    for ID in $NODE_IDS; do
        dcos node | grep $ID | awk '{print $2}'
    done
}

get_private_addresses_for_windows_public_agents() {
    #
    # Returns the private addresses for the Windows Public Mesos agents
    #
    NODE_IDS=$(dcos node --json | python -c "import json, sys ; d = json.load(sys.stdin) ; v = [s['id'] for s in d if s['attributes']['os'] == 'windows' and 'public_ip' in s['attributes'].keys() and  s['attributes']['public_ip'] == 'yes'] ; print('\n'.join(v))")
    for ID in $NODE_IDS; do
        dcos node | grep $ID | awk '{print $2}'
    done
}

get_private_addresses_for_windows_private_agents() {
    #
    # Returns the private addresses for the Windows Private Mesos agents
    #
    NODE_IDS=$(dcos node --json | python -c "import json, sys ; d = json.load(sys.stdin) ; v = [s['id'] for s in d if s['attributes']['os'] == 'windows' and 'public_ip' not in s['attributes'].keys()] ; print('\n'.join(v))")
    for ID in $NODE_IDS; do
        dcos node | grep $ID | awk '{print $2}'
    done
}

collect_linux_masters_logs() {
    #
    # Collects the Linux masters' logs and downloads them via SCP on the
    # local location LOCAL_LOGS_DIR, passed as first parameter to the function.
    #
    local LOCAL_LOGS_DIR="$1"
    COLLECT_LINUX_LOGS_SCRIPT="$DIR/../utils/collect-linux-machine-logs.sh"
    for i in `seq 0 $(($LINUX_MASTER_COUNT - 1))`; do
        TMP_LOGS_DIR="/tmp/master_$i"
        MASTER_SSH_PORT="220$i"
        upload_files_via_scp $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS $MASTER_SSH_PORT "/tmp/collect-logs.sh" $COLLECT_LINUX_LOGS_SCRIPT
        run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS $MASTER_SSH_PORT "/tmp/collect-logs.sh $TMP_LOGS_DIR"
        download_files_via_scp $MASTER_PUBLIC_ADDRESS $MASTER_SSH_PORT $TMP_LOGS_DIR "${LOCAL_LOGS_DIR}/"
    done
}

collect_linux_agents_logs() {
    #
    # Collects the Linux agents' logs and downloads them locally. The local logs directory
    # is given as the first parameter and the private addresses for the agents are given
    # as the second parameter. The first master is used as a gateway to reach the Linux
    # agents via the private address.
    #
    local LOCAL_LOGS_DIR="$1"
    local AGENTS_IPS="$2"
    upload_files_via_scp $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "22" "/tmp/collect-logs.sh" "$DIR/../utils/collect-linux-machine-logs.sh"
    upload_files_via_scp $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "22" "/tmp/utils.sh" "$DIR/../utils/utils.sh"
    for IP in $AGENTS_IPS; do
        run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "22" "source /tmp/utils.sh && upload_files_via_scp $LINUX_ADMIN $IP 22 /tmp/collect-logs.sh /tmp/collect-logs.sh"
        AGENT_LOGS_DIR="/tmp/agent_$IP"
        run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "22" "source /tmp/utils.sh && run_ssh_command $LINUX_ADMIN $IP 22 '/tmp/collect-logs.sh $AGENT_LOGS_DIR'"
        run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "22" "source /tmp/utils.sh && rm -rf $AGENT_LOGS_DIR && download_files_via_scp $IP 22 $AGENT_LOGS_DIR $AGENT_LOGS_DIR"
        download_files_via_scp $MASTER_PUBLIC_ADDRESS 22 $AGENT_LOGS_DIR "${LOCAL_LOGS_DIR}/"
    done
}

collect_windows_agents_logs() {
    #
    # Collects the Windows agents' logs and downloads them locally. The local logs directory
    # is given as the first parameter and the private addresses for the agents are given
    # as the second parameter. The first master is used as a gateway to reach the Windows
    # agents via the private address.
    #
    local LOCAL_LOGS_DIR="$1"
    local AGENTS_IPS="$2"
    upload_files_via_scp $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "22" "/tmp/utils.sh" "$DIR/../utils/utils.sh"
    for IP in $AGENTS_IPS; do
        AGENT_LOGS_DIR="/tmp/agent_$IP"
        run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "22" "source /tmp/utils.sh && mount_smb_share $IP $WIN_AGENT_ADMIN $WIN_AGENT_ADMIN_PASSWORD && mkdir -p $AGENT_LOGS_DIR/logs"
        for SERVICE in "epmd" "mesos" "spartan"; do
            run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "22" "cp -rf /mnt/$IP/DCOS/$SERVICE/log $AGENT_LOGS_DIR/logs/$SERVICE"
        done
        download_files_via_scp $MASTER_PUBLIC_ADDRESS 22 $AGENT_LOGS_DIR "${LOCAL_LOGS_DIR}/"
    done
}

collect_logs() {
    #
    # Collect logs from all the deployment nodes and upload them to the log server
    #
    echo "Collecting logs from all the DCOS nodes"
    LOGS_DIR="/tmp/dcos-logs/$BUILD_ID"
    rm -rf $LOGS_DIR
    mkdir -p $LOGS_DIR

    # Collect logs from all the Linux master node(s)
    echo "Collecting Linux master logs"
    MASTERS_LOGS_DIR="$LOGS_DIR/linux_masters"
    mkdir -p $MASTERS_LOGS_DIR
    collect_linux_masters_logs "$MASTERS_LOGS_DIR"

    # From now on, use the first Linux master as a proxy node to collect logs
    # from all the other Linux machines.
    run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "22" 'mkdir -p $HOME/.ssh && chmod 700 $HOME/.ssh'
    upload_files_via_scp $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "22" '$HOME/.ssh/id_rsa' "$HOME/.ssh/id_rsa"

    dcos config set core.dcos_url "http://${MASTER_PUBLIC_ADDRESS}:80"

    # Collect logs from all the public Windows nodes(s)
    WIN_PUBLIC_LOGS_DIR="$LOGS_DIR/windows_public_agents"
    mkdir -p $WIN_PUBLIC_LOGS_DIR
    IPS=$(get_private_addresses_for_windows_public_agents)
    collect_windows_agents_logs "$WIN_PUBLIC_LOGS_DIR" "$IPS"

    if [[ $WIN_PRIVATE_AGENT_COUNT -gt 0 ]]; then
        # Collect logs from all the private Windows nodes(s)
        WIN_PRIVATE_LOGS_DIR="$LOGS_DIR/windows_private_agents"
        mkdir -p $WIN_PRIVATE_LOGS_DIR
        IPS=$(get_private_addresses_for_windows_private_agents)
        collect_windows_agents_logs "$WIN_PRIVATE_LOGS_DIR" "$IPS"
    fi

    if [[ $LINUX_PUBLIC_AGENT_COUNT -gt 0 ]]; then
        # Collect logs from all the public Linux node(s)
        LINUX_PUBLIC_LOGS_DIR="$LOGS_DIR/linux_public_agents"
        mkdir -p $LINUX_PUBLIC_LOGS_DIR
        IPS=$(get_private_addresses_for_linux_public_agents)
        collect_linux_agents_logs "$LINUX_PUBLIC_LOGS_DIR" "$IPS"
    fi

    if [[ $LINUX_PRIVATE_AGENT_COUNT -gt 0 ]]; then
        # Collect logs from all the private Linux node(s)
        LINUX_PRIVATE_LOGS_DIR="$LOGS_DIR/linux_private_agents"
        mkdir -p $LINUX_PRIVATE_LOGS_DIR
        IPS=$(get_private_addresses_for_linux_private_agents)
        collect_linux_agents_logs "$LINUX_PRIVATE_LOGS_DIR" "$IPS"
    fi

    # Upload the logs to log server
    upload_files_via_scp $LOG_SERVER_USER $LOG_SERVER_ADDRESS "22" "${REMOTE_LOGS_DIR}/" $LOGS_DIR
    rm -rf $LOGS_DIR
}

# Deploy DCOS master + slave nodes
$DIR/../acs-engine-dcos-deploy.sh || handle_command_error "ERROR: Failed to deploy DCOS on Azure" "False"
echo "Linux master load balancer public address: $MASTER_PUBLIC_ADDRESS"
echo "Windows agent load balancer public address: $WIN_AGENT_PUBLIC_ADDRESS"

# Open DCOS API & GUI port
open_dcos_port || handle_command_error "ERROR: Failed to open the DCOS port" "True"

# Run the functional tests
run_functional_tests || handle_command_error "ERROR: Failed to run functional tests" "True"

# Collect all the logs in the DCOS deployments
collect_logs || handle_command_error "ERROR: Failed to collect logs" "False"

# Do the final cleanup
job_cleanup

echo "Successfully tested an Azure DCOS deployment with the latest Mesos binaries"
