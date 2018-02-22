#!/usr/bin/env bash

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
IIS_TEMPLATE="$DIR/templates/marathon-iis.json"
FETCHER_HTTP_TEMPLATE="$DIR/templates/marathon-fetcher-http.json"
FETCHER_HTTPS_TEMPLATE="$DIR/templates/marathon-fetcher-https.json"
FETCHER_LOCAL_TEMPLATE="$DIR/templates/marathon-fetcher-local.json"
FETCHER_LOCAL_FILE_URL="http://dcos-win.westus.cloudapp.azure.com/dcos-windows/testing/fetcher-test.zip"
FETCHER_FILE_MD5="07D6BB2D5BAED0C40396C229259CAA71"
LOG_SERVER_ADDRESS="10.3.1.6"
LOG_SERVER_USER="logs"
REMOTE_LOGS_DIR="/data/dcos-testing"
LOGS_BASE_URL="http://dcos-win.westus.cloudapp.azure.com/dcos-testing"
JENKINS_SERVER_URL="https://mesos-jenkins.westus.cloudapp.azure.com:8443"
UTILS_FILE="$DIR/utils/utils.sh"
BUILD_OUTPUTS_URL="$LOGS_BASE_URL/$BUILD_ID"
PARAMETERS_FILE="$WORKSPACE/build-parameters.txt"
TEMP_LOGS_DIR="$WORKSPACE/$BUILD_ID"
rm -f $PARAMETERS_FILE && touch $PARAMETERS_FILE && mkdir -p $TEMP_LOGS_DIR && \
rm -rf $HOME/.dcos && source $UTILS_FILE || exit 1


job_cleanup() {
    #
    # Deletes the Azure resource group used for the deployment
    #
    echo "Cleanup in progress for the current Azure DC/OS deployment"
    az group delete --yes --name $AZURE_RESOURCE_GROUP --output table || {
        echo "ERROR: Failed to delete the resource group"
        return 1
    }
    echo "Finished the environment cleanup"
}

upload_logs() {
    #
    # Uploads the logs to the log server
    #
    # Copy the Jenkins console as well
    wget --no-check-certificate "${JENKINS_SERVER_URL}/job/${JOB_NAME}/${BUILD_NUMBER}/consoleText" -O $TEMP_LOGS_DIR/jenkins-console.log || return 1
    echo "Uploading logs to the log server"
    upload_files_via_scp $LOG_SERVER_USER $LOG_SERVER_ADDRESS "22" "${REMOTE_LOGS_DIR}/" $TEMP_LOGS_DIR || return 1
    echo "All the logs available at: $BUILD_OUTPUTS_URL"
    echo "BUILD_OUTPUTS_URL=$BUILD_OUTPUTS_URL" >> $PARAMETERS_FILE
    rm -rf $TEMP_LOGS_DIR || return 1
}

check_open_port() {
    #
    # Checks with a timeout if a particular port (TCP or UDP) is open (nc tool is used for this)
    #
    local ADDRESS="$1"
    local PORT="$2"
    local TIMEOUT=900
    echo "Checking, with a timeout of $TIMEOUT seconds, if the port $PORT is open at the address: $ADDRESS"
    SECONDS=0
    while true; do
        if [[ $SECONDS -gt $TIMEOUT ]]; then
            echo "ERROR: Port $PORT didn't open at $ADDRESS within $TIMEOUT seconds"
            return 1
        fi
        nc -v -z "$ADDRESS" "$PORT" &>/dev/null && break || sleep 1
    done
    echo "Success: Port $PORT is open at address $ADDRESS"
}

open_dcos_port() {
    #
    # This function opens the GUI endpoint on the first master unit
    #
    echo "Open DC/OS port 80"
    MASTER_LB_NAME=$(az network lb list --resource-group $AZURE_RESOURCE_GROUP --output table | grep 'dcos-master' | awk '{print $2}') || {
        echo "ERROR: Failed to get the master load balancer name"
        return 1
    }
    # NOTE: We take the fist master NIC
    MASTER_NIC_NAME=$(az network nic list --resource-group $AZURE_RESOURCE_GROUP --output table | grep 'dcos-master' | awk '{print $3}' | head -1) || {
        echo "ERROR: Failed to get the master NIC name"
        return 1
    }
    NAT_RULE_NAME="DCOS_Port_80"
    echo "Create inbound NAT rule for DC/OS port 80"
    az network lb inbound-nat-rule create --resource-group $AZURE_RESOURCE_GROUP --lb-name $MASTER_LB_NAME \
                                          --name $NAT_RULE_NAME --protocol Tcp --frontend-port 80 --backend-port 80 --output table || {
        echo "ERROR: Failed to create load balancer inbound NAT rule"
        return 1
    }
    az network nic ip-config inbound-nat-rule add --resource-group $AZURE_RESOURCE_GROUP --lb-name $MASTER_LB_NAME --nic-name $MASTER_NIC_NAME \
                                                  --inbound-nat-rule $NAT_RULE_NAME --ip-config-name ipConfigNode --output table || {
        echo "ERROR: Failed to create ip-config inbound-nat-rule"
        return 1
    }
    echo "Add security group rule for DC/OS port 80"
    MASTER_SG_NAME=$(az network nsg list --resource-group $AZURE_RESOURCE_GROUP --output table | grep 'dcos-master' | awk '{print $2}') || {
        echo "ERROR: Failed to get the master security name"
        return 1
    }
    az network nsg rule create --resource-group $AZURE_RESOURCE_GROUP --nsg-name $MASTER_SG_NAME --name $NAT_RULE_NAME \
                               --access Allow --protocol Tcp --direction Inbound --priority 100 --destination-port-range 80 --output table || {
        echo "ERROR: Failed to create the DC/OS port security group rule for the master node"
        return 1
    }
    check_open_port "$MASTER_PUBLIC_ADDRESS" "80" || return 1
}

deploy_iis() {
    #
    # - Deploys an IIS app via marathon
    # - Checks if marathon successfully launched a Mesos task
    # - Checks if the IIS exposed public port 80 is open
    #
    echo "Deploying the IIS marathon template on DC/OS"
    dcos marathon app add $IIS_TEMPLATE || {
        echo "ERROR: Failed to deploy the IIS marathon app"
        return 1
    }
    APP_NAME=$(get_marathon_application_name $IIS_TEMPLATE)
    $DIR/utils/check-marathon-app-health.py --name $APP_NAME || {
        echo "ERROR: Failed to get $APP_NAME application health checks"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }
    check_open_port "$WIN_AGENT_PUBLIC_ADDRESS" "80" || {
        echo "EROR: Port 80 is not open for the application: $APP_NAME"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }
    echo "IIS successfully deployed on DCOS"
    dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
    remove_dcos_marathon_app $APP_NAME || return 1
}

check_custom_attributes() {
    #
    # Check if the custom attributes are set for the slaves
    #
    $DIR/utils/check-custom-attributes.py || return 1
    echo "The custom attributes are correctly set"
}

test_mesos_fetcher() {
    local APPLICATION_NAME="$1"
    $DIR/utils/check-marathon-app-health.py --name $APPLICATION_NAME || return 1
    run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "sudo apt-get update && sudo apt-get install python3-pip -y && sudo pip3 install -U pywinrm==0.2.1" &>/dev/null || {
        echo "ERROR: Failed to install dependencies on the first master used as a proxy"
        return 1
    }
    sudo apt-get update -y >/dev/null && sudo apt-get install jq -y >/dev/null || {
        echo "ERROR: Failed to install jq dependency"
        return 1
    }
    TASK_HOST=$(dcos marathon app show $APPLICATION_NAME | jq -r ".tasks[0].host")
    upload_files_via_scp $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "/tmp/wsmancmd.py" "$DIR/utils/wsmancmd.py" || {
        echo "ERROR: Failed to copy wsmancmd.py to the proxy master node"
        return 1
    }
    DOCKER_CONTAINER_ID=$(run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "/tmp/wsmancmd.py -H $TASK_HOST -s -a basic -u $WIN_AGENT_ADMIN -p $WIN_AGENT_ADMIN_PASSWORD 'docker ps -q'") || {
        echo "ERROR: Failed to get the Docker container ID from the host: $TASK_HOST"
        return 1
    }
    MD5_CHECKSUM=$(run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "/tmp/wsmancmd.py -H $TASK_HOST -s -a basic -u $WIN_AGENT_ADMIN -p $WIN_AGENT_ADMIN_PASSWORD 'docker exec $DOCKER_CONTAINER_ID powershell (Get-FileHash -Algorithm MD5 -Path C:\mesos\sandbox\fetcher-test.zip).Hash'") || {
        echo "ERROR: Failed to get the fetcher file MD5 checksum"
        return 1
    }
    if [[ "$MD5_CHECKSUM" != "$FETCHER_FILE_MD5" ]]; then
        echo "ERROR: Fetcher file MD5 checksum is not correct. The checksum found is $MD5_CHECKSUM and the expected one is $FETCHER_FILE_MD5"
        return 1
    fi
    echo "The MD5 checksum for the fetcher file was successfully checked"
}

remove_dcos_marathon_app() {
    local APPLICATION_NAME="$1"
    dcos marathon app remove $APPLICATION_NAME || return 1
    while [[ "$(dcos marathon app list | grep $APPLICATION_NAME)" != "" ]]; do
        echo "Waiting for application $APPLICATION_NAME to be removed"
        sleep 5
    done
}

get_marathon_application_name() {
    local TEMPLATE_PATH="$1"
    cat $TEMPLATE_PATH | python -c "import json,sys ; input = json.load(sys.stdin) ; print(input['id'])"
}

test_mesos_fetcher_local() {
    #
    # Test Mesos fetcher with local resource
    #
    echo "Testing Mesos fetcher using local resource"
    upload_files_via_scp $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "/tmp/utils.sh" "$DIR/utils/utils.sh" || {
        echo "ERROR: Failed to scp utils.sh"
        return 1
    }
    WIN_PUBLIC_IPS=$($DIR/utils/dcos-node-addresses.py --operating-system 'windows' --role 'public') || {
        echo "ERROR: Failed to get the DC/OS Windows public agents addresses"
        return 1
    }
    # Download the fetcher test file locally to all the targeted nodes
    for IP in $WIN_PUBLIC_IPS; do
        run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "source /tmp/utils.sh && mount_smb_share $IP $WIN_AGENT_ADMIN $WIN_AGENT_ADMIN_PASSWORD && sudo wget $FETCHER_LOCAL_FILE_URL -O /mnt/$IP/fetcher-test.zip" || {
            echo "ERROR: Failed to copy the fetcher resource file to Windows public agent $IP"
            return 1
        }
    done
    dcos marathon app add $FETCHER_LOCAL_TEMPLATE || return 1
    APP_NAME=$(get_marathon_application_name $FETCHER_LOCAL_TEMPLATE)
    test_mesos_fetcher $APP_NAME || {
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        echo "ERROR: Failed to test Mesos fetcher using local resource"
        return 1
    }
    echo "Successfully tested Mesos fetcher using local resource"
    dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
    remove_dcos_marathon_app $APP_NAME || return 1
}

test_mesos_fetcher_remote_http() {
    #
    # Test Mesos fetcher with remote resource (http)
    #
    echo "Testing Mesos fetcher using remote http resource"
    dcos marathon app add $FETCHER_HTTP_TEMPLATE || return 1
    APP_NAME=$(get_marathon_application_name $FETCHER_HTTP_TEMPLATE)
    test_mesos_fetcher $APP_NAME || {
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        echo "ERROR: Failed to test Mesos fetcher using remote http resource"
        return 1
    }
    echo "Successfully tested Mesos fetcher using remote http resource"
    dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
    remove_dcos_marathon_app $APP_NAME || return 1
}

test_mesos_fetcher_remote_https() {
    #
    # Test Mesos fetcher with remote resource (https)
    #
    echo "Testing Mesos fetcher using remote https resource"
    dcos marathon app add $FETCHER_HTTPS_TEMPLATE || return 1
    APP_NAME=$(get_marathon_application_name $FETCHER_HTTPS_TEMPLATE)
    test_mesos_fetcher $APP_NAME || {
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        echo "ERROR: Failed to test Mesos fetcher using remote https resource"
        return 1
    }
    echo "Successfully tested Mesos fetcher using remote https resource"
    dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
    remove_dcos_marathon_app $APP_NAME || return 1
}


test_windows_agent_dcos_dns() {
    #
    # Executes on the AGENT_IP via WinRM, an 'nslookup.exe' command to resolve
    # 'master.mesos' and 'leader.mesos'. This script assumes that PyWinRM is
    # already installed on the first master node that is used as a proxy.
    #
    local AGENT_IP="$1"
    upload_files_via_scp $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "/tmp/wsmancmd.py" "$DIR/utils/wsmancmd.py" || return 1
    for DNS_RECORD in leader.mesos master.mesos; do
        echo -e "Trying to resolve $DNS_RECORD on Windows agent: $AGENT_IP"
        run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "/tmp/wsmancmd.py -H $AGENT_IP -s -a basic -u $WIN_AGENT_ADMIN -p $WIN_AGENT_ADMIN_PASSWORD --powershell 'Resolve-DnsName $DNS_RECORD'" || return 1
        echo -e "\n"
    done
    echo -e "Successfully resolved DC/OS Mesos DNS records on Windows slave: ${AGENT_IP}"
}

test_dcos_dns() {
    #
    # Tries to resolve 'leader.mesos' and 'master.masos' from all the Windows
    # slaves. A remote PowerShell command is executed via WinRM. This ensures
    # that the DC/OS dns component on Windows (Spartan or dcos-net) is correctly
    # set up
    #
    echo "Testing DC/OS DNS on the Windows slaves"
    run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "sudo apt-get update && sudo apt-get install python3-pip -y && sudo pip3 install -U pywinrm==0.2.1" &>/dev/null || {
        echo "ERROR: Failed to install dependencies on the first master used as a proxy"
        return 1
    }
    if [[ $WIN_PRIVATE_AGENT_COUNT -gt 0 ]]; then
        IPS=$($DIR/utils/dcos-node-addresses.py --operating-system 'windows' --role 'private') || return 1
        for IP in $IPS; do
            echo "Checking DNS for Windows private agent: $IP"
            test_windows_agent_dcos_dns "$IP" || return 1
        done
    fi
    if [[ $WIN_PUBLIC_AGENT_COUNT -gt 0 ]]; then
        IPS=$($DIR/utils/dcos-node-addresses.py --operating-system 'windows' --role 'public') || return 1
        for IP in $IPS; do
            echo "Checking DNS for Windows public agent: $IP"
            test_windows_agent_dcos_dns "$IP" || return 1
        done
    fi
}

run_functional_tests() {
    #
    # Run the following DC/OS functional tests:
    #  - Deploy a simple IIS marathon app and test if the exposed port 80 is open
    #  - Check if the custom attributes are set
    #  - Check DC/OS DNS functionality from the Windows node
    #  - Test Mesos fetcher with local resource
    #  - Test Mesos fetcher with remote http resource
    #  - Test Mesos fetcher with remote https resource
    #
    check_custom_attributes || return 1
    deploy_iis || return 1
    test_dcos_dns || return 1
    test_mesos_fetcher_local || return 1
    test_mesos_fetcher_remote_http || return 1
    test_mesos_fetcher_remote_https || return 1
}

collect_linux_masters_logs() {
    #
    # Collects the Linux masters' logs and downloads them via SCP on the
    # local location LOCAL_LOGS_DIR, passed as first parameter to the function.
    #
    local LOCAL_LOGS_DIR="$1"
    local COLLECT_LINUX_LOGS_SCRIPT="$DIR/utils/collect-linux-machine-logs.sh"
    for i in `seq 0 $(($LINUX_MASTER_COUNT - 1))`; do
        TMP_LOGS_DIR="/tmp/master_$i"
        MASTER_SSH_PORT="220$i"
        upload_files_via_scp $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS $MASTER_SSH_PORT "/tmp/collect-logs.sh" $COLLECT_LINUX_LOGS_SCRIPT || return 1
        run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS $MASTER_SSH_PORT "/tmp/collect-logs.sh $TMP_LOGS_DIR" || return 1
        download_files_via_scp $MASTER_PUBLIC_ADDRESS $MASTER_SSH_PORT $TMP_LOGS_DIR "${LOCAL_LOGS_DIR}/" || return 1
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
    upload_files_via_scp $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "/tmp/collect-logs.sh" "$DIR/utils/collect-linux-machine-logs.sh" || return 1
    upload_files_via_scp $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "/tmp/utils.sh" "$DIR/utils/utils.sh" || return 1
    for IP in $AGENTS_IPS; do
        run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "source /tmp/utils.sh && upload_files_via_scp $LINUX_ADMIN $IP 22 /tmp/collect-logs.sh /tmp/collect-logs.sh" || return 1
        AGENT_LOGS_DIR="/tmp/agent_$IP"
        run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "source /tmp/utils.sh && run_ssh_command $LINUX_ADMIN $IP 22 '/tmp/collect-logs.sh $AGENT_LOGS_DIR'" || return 1
        run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "source /tmp/utils.sh && rm -rf $AGENT_LOGS_DIR && download_files_via_scp $IP 22 $AGENT_LOGS_DIR $AGENT_LOGS_DIR" || return 1
        download_files_via_scp $MASTER_PUBLIC_ADDRESS "2200" $AGENT_LOGS_DIR "${LOCAL_LOGS_DIR}/" || return 1
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
    upload_files_via_scp $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "/tmp/utils.sh" "$DIR/utils/utils.sh" || return 1
    for IP in $AGENTS_IPS; do
        AGENT_LOGS_DIR="/tmp/agent_$IP"
        run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "source /tmp/utils.sh && mount_smb_share $IP $WIN_AGENT_ADMIN $WIN_AGENT_ADMIN_PASSWORD && mkdir -p $AGENT_LOGS_DIR/logs" || return 1
        for SERVICE in "epmd" "mesos" "spartan"; do
            run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" "if [[ -e /mnt/$IP/DCOS/$SERVICE/log ]] ; then cp -rf /mnt/$IP/DCOS/$SERVICE/log $AGENT_LOGS_DIR/logs/$SERVICE ; fi" || return 1
        done
        download_files_via_scp $MASTER_PUBLIC_ADDRESS "2200" $AGENT_LOGS_DIR "${LOCAL_LOGS_DIR}/" || return 1
    done
}

collect_dcos_nodes_logs() {
    #
    # Collect logs from all the deployment nodes and upload them to the log server
    #
    echo "Collecting logs from all the DC/OS nodes"
    dcos node --json > $TEMP_LOGS_DIR/dcos-nodes.json

    # Collect logs from all the Linux master node(s)
    echo "Collecting Linux master logs"
    MASTERS_LOGS_DIR="$TEMP_LOGS_DIR/linux_masters"
    mkdir -p $MASTERS_LOGS_DIR || return 1
    collect_linux_masters_logs "$MASTERS_LOGS_DIR" || return 1

    # From now on, use the first Linux master as a proxy node to collect logs
    # from all the other Linux machines.
    run_ssh_command $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" 'mkdir -p $HOME/.ssh && chmod 700 $HOME/.ssh' || return 1
    upload_files_via_scp $LINUX_ADMIN $MASTER_PUBLIC_ADDRESS "2200" '$HOME/.ssh/id_rsa' "$HOME/.ssh/id_rsa" || return 1

    # Collect logs from all the public Windows nodes(s)
    echo "Collecting Windows public agents logs"
    WIN_PUBLIC_LOGS_DIR="$TEMP_LOGS_DIR/windows_public_agents"
    mkdir -p $WIN_PUBLIC_LOGS_DIR || return 1
    IPS=$($DIR/utils/dcos-node-addresses.py --operating-system 'windows' --role 'public') || return 1
    collect_windows_agents_logs "$WIN_PUBLIC_LOGS_DIR" "$IPS" || return 1

    if [[ $WIN_PRIVATE_AGENT_COUNT -gt 0 ]]; then
        echo "Collecting Windows private agents logs"
        # Collect logs from all the private Windows nodes(s)
        WIN_PRIVATE_LOGS_DIR="$TEMP_LOGS_DIR/windows_private_agents"
        mkdir -p $WIN_PRIVATE_LOGS_DIR  || return 1
        IPS=$($DIR/utils/dcos-node-addresses.py --operating-system 'windows' --role 'private') || return 1
        collect_windows_agents_logs "$WIN_PRIVATE_LOGS_DIR" "$IPS" || return 1
    fi

    if [[ $LINUX_PUBLIC_AGENT_COUNT -gt 0 ]]; then
        echo "Collecting Linux public agents logs"
        # Collect logs from all the public Linux node(s)
        LINUX_PUBLIC_LOGS_DIR="$TEMP_LOGS_DIR/linux_public_agents"
        mkdir -p $LINUX_PUBLIC_LOGS_DIR || return 1
        IPS=$($DIR/utils/dcos-node-addresses.py --operating-system 'linux' --role 'public') || return 1
        collect_linux_agents_logs "$LINUX_PUBLIC_LOGS_DIR" "$IPS" || return 1
    fi

    if [[ $LINUX_PRIVATE_AGENT_COUNT -gt 0 ]]; then
        echo "Collecting Linux private agents logs"
        # Collect logs from all the private Linux node(s)
        LINUX_PRIVATE_LOGS_DIR="$TEMP_LOGS_DIR/linux_private_agents"
        mkdir -p $LINUX_PRIVATE_LOGS_DIR || return 1
        IPS=$($DIR/utils/dcos-node-addresses.py --operating-system 'linux' --role 'private') || return 1
        collect_linux_agents_logs "$LINUX_PRIVATE_LOGS_DIR" "$IPS" || return 1
    fi
}

install_dcos_cli() {
    DCOS_CLI_BASE_URL="https://downloads.dcos.io/binaries/cli/linux/x86-64"
    if [[ "$DCOS_VERSION" = "1.8.8" ]]; then
        DCOS_CLI_URL="$DCOS_CLI_BASE_URL/dcos-1.8/dcos"
    elif [[ "$DCOS_VERSION" = "1.9.0" ]]; then
        DCOS_CLI_URL="$DCOS_CLI_BASE_URL/dcos-1.9/dcos"
    elif [[ "$DCOS_VERSION" = "1.10.0" ]]; then
        DCOS_CLI_URL="$DCOS_CLI_BASE_URL/dcos-1.10/dcos"
    else
        echo "ERROR: Cannot find the DC/OS cli url for the version: $DCOS_VERSION"
        return 1
    fi
    DCOS_BINARY_FILE="/usr/local/bin/dcos"
    sudo curl $DCOS_CLI_URL -o $DCOS_BINARY_FILE && \
    sudo chmod +x $DCOS_BINARY_FILE || {
        echo "ERROR: Failed to install the DC/OS CLI"
        return 1
    }
    if [[ "$DCOS_VERSION" = "1.8.8" ]] || [[ "$DCOS_VERSION" = "1.9.0" ]]; then
        dcos config set core.dcos_url "http://${MASTER_PUBLIC_ADDRESS}:80" || return 1
    else
        dcos cluster setup "http://${MASTER_PUBLIC_ADDRESS}:80" || return 1
    fi
}

check_exit_code() {
    if [[ $? -eq 0 ]]; then
        return 0
    fi
    local COLLECT_LOGS=$1
    if [[ "$COLLECT_LOGS" = true ]]; then
        collect_dcos_nodes_logs || echo "ERROR: Failed to collect DC/OS nodes logs"
    fi
    upload_logs || echo "ERROR: Failed to upload logs to log server"
    MSG="Failed to test the Azure $DCOS_DEPLOYMENT_TYPE DC/OS deployment with "
    MSG+="the latest builds from: ${DCOS_WINDOWS_BOOTSTRAP_URL}"
    echo "STATUS=FAIL" >> $PARAMETERS_FILE
    echo "EMAIL_TITLE=[${JOB_NAME}] FAIL" >> $PARAMETERS_FILE
    echo "MESSAGE=$MSG" >> $PARAMETERS_FILE
    echo "LOGS_URLS=$BUILD_OUTPUTS_URL/jenkins-console.log" >> $PARAMETERS_FILE
    job_cleanup
    exit 1
}

# Install latest stable ACS Engine tool
$DIR/utils/install-latest-stable-acs-engine.sh
check_exit_code false

# Deploy DC/OS master + slave nodes
$DIR/acs-engine-dcos-deploy.sh
check_exit_code false
echo "Linux master load balancer public address: $MASTER_PUBLIC_ADDRESS"
echo "Windows agent load balancer public address: $WIN_AGENT_PUBLIC_ADDRESS"

# Open DC/OS API & GUI port
open_dcos_port
check_exit_code false

# Install the proper DC/OS cli version
install_dcos_cli
check_exit_code false

# Run the functional tests
run_functional_tests
check_exit_code true

# Collect all the logs in the DC/OS deployments
collect_dcos_nodes_logs || echo "ERROR: Failed to collect DC/OS nodes logs"
upload_logs || echo "ERROR: Failed to upload logs to log server"

MSG="Successfully tested the Azure $DCOS_DEPLOYMENT_TYPE DC/OS deployment with "
MSG+="the latest builds from: ${DCOS_WINDOWS_BOOTSTRAP_URL}"
echo "STATUS=PASS" >> $PARAMETERS_FILE
echo "EMAIL_TITLE=[${JOB_NAME}] PASS" >> $PARAMETERS_FILE
echo "MESSAGE=$MSG" >> $PARAMETERS_FILE

# Do the final cleanup
job_cleanup

echo "Successfully tested an Azure DC/OS deployment with the latest DC/OS builds"
