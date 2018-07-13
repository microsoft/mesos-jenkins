#!/usr/bin/env bash

export AZURE_RESOURCE_GROUP="${JOB_NAME}-${BUILD_ID}"
export LINUX_ADMIN="azureuser"
export WIN_AGENT_PUBLIC_POOL="winpubpool"
export WIN_AGENT_PRIVATE_POOL="winpripool"
export LINUX_AGENT_PUBLIC_POOL="linpubpool"
export LINUX_AGENT_PRIVATE_POOL="linpripool"
export LINUX_MASTER_DNS_PREFIX="dcos-testing-lin-master-${BUILD_ID}"
export WIN_AGENT_DNS_PREFIX="dcos-testing-win-agent-${BUILD_ID}"
export LINUX_AGENT_DNS_PREFIX="dcos-testing-lin-agent-${BUILD_ID}"
export WIN_AGENT_ADMIN="azureuser"
if [[ -z $AZURE_REGION ]]; then
    echo "ERROR: Parameter AZURE_REGION is not set"
    exit 1
fi
if [[ $(echo "$AZURE_REGION" | grep "\s") ]]; then
    echo "ERROR: The AZURE_REGION parameter must not contain any spaces"
fi
if [[ -z $DOCKER_HUB_USER ]]; then
    echo "ERROR: Parameter DOCKER_HUB_USER is not set"
    exit 1
fi
if [[ -z $DOCKER_HUB_USER_PASSWORD ]]; then
    echo "ERROR: Parameter DOCKER_HUB_USER_PASSWORD is not set"
    exit 1
fi

if [[ "$DCOS_DEPLOYMENT_TYPE" = "simple" ]]; then
    export DCOS_AZURE_PROVIDER_PACKAGE_ID="5a6b7b92820dc4a7825c84f0a96e012e0fcc8a6b"
    export LINUX_MASTER_COUNT="1"
    export LINUX_PUBLIC_AGENT_COUNT="0"
    export LINUX_PRIVATE_AGENT_COUNT="0"
    export WIN_PUBLIC_AGENT_COUNT="1"
    export WIN_PRIVATE_AGENT_COUNT="0"
elif [[ "$DCOS_DEPLOYMENT_TYPE" = "hybrid" ]]; then
    export DCOS_AZURE_PROVIDER_PACKAGE_ID="327392a609d77d411886216d431e00581a8612f7"
    export LINUX_MASTER_COUNT="3"
    export LINUX_PUBLIC_AGENT_COUNT="1"
    export LINUX_PRIVATE_AGENT_COUNT="1"
    export WIN_PUBLIC_AGENT_COUNT="2"
    export WIN_PRIVATE_AGENT_COUNT="2"
else
    echo "ERROR: $DCOS_DEPLOYMENT_TYPE DCOS_DEPLOYMENT_TYPE is not supported"
    exit 1
fi
if [[ -z $DCOS_DIR ]]; then
    export DCOS_DIR="$WORKSPACE/dcos_$BUILD_ID"
fi
if [[ -z $AZURE_KEYVAULT_NAME ]] || [[ -z $PRIVATE_KEY_SECRET_NAME ]] || [[ -z $PUBLIC_KEY_SECRET_NAME ]] || [[ -z $WIN_PASS_SECRET_NAME ]]; then
    echo "ERROR: KEYVAULT_NAME, PRIVATE_KEY_SECRET_NAME, PUBLIC_KEY_SECRET_NAME and WIN_PASS_SECRET_NAME are mandatory"
    exit 1
fi
if [[ -z $JOB_ARTIFACTS_DIR ]]; then
    echo "ERROR: JOB_ARTIFACTS_DIR is not set"
    exit 1
fi
if [[ ! -d $JOB_ARTIFACTS_DIR ]]; then
    echo "The job artifacts directory $JOB_ARTIFACTS_DIR does not exist. Creating it"
    mkdir -p $JOB_ARTIFACTS_DIR
fi
export BUILD_ARTIFACTS_DIR="${JOB_ARTIFACTS_DIR}/${BUILD_ID}"
if [[ -e $BUILD_ARTIFACTS_DIR ]]; then
    echo "Build artifacts directory $BUILD_ARTIFACTS_DIR already exists. Deleting it and creating a new one"
    rm -rf $BUILD_ARTIFACTS_DIR
fi
echo "Creating a new build artifacts directory at $BUILD_ARTIFACTS_DIR"
mkdir -p $BUILD_ARTIFACTS_DIR

# LINUX_PRIVATE_IPS and WINDOWS_PRIVATE_IPS will be set later on in the script
export LINUX_PRIVATE_IPS=""
export WINDOWS_PRIVATE_IPS=""

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MASTER_PUBLIC_ADDRESS="${LINUX_MASTER_DNS_PREFIX}.${AZURE_REGION}.cloudapp.azure.com"
WIN_AGENT_PUBLIC_ADDRESS="${WIN_AGENT_DNS_PREFIX}.${AZURE_REGION}.cloudapp.azure.com"
LINUX_AGENT_PUBLIC_ADDRESS="${LINUX_AGENT_DNS_PREFIX}.${AZURE_REGION}.cloudapp.azure.com"
WINDOWS_APP_CONTAINER_TEMPLATE="$DIR/templates/marathon/windows-app-container.json"
WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE="${WORKSPACE}/windows-app-container.json"
DOCKER_PRIVATE_TEMPLATE="$DIR/templates/marathon/docker-private-image.json"
DOCKER_PRIVATE_RENDERED_TEMPLATE="${WORKSPACE}/docker-private-image.json"
IIS_TEMPLATE="$DIR/templates/marathon/iis.json"
WINDOWS_APP_PUBLISH_TEMPLATE="$DIR/templates/marathon/windows-app-publish.json"
WINDOWS_APP_PUBLISH_RENDERED_TEMPLATE="${WORKSPACE}/windows-app-publish.json"
FETCHER_HTTP_TEMPLATE="$DIR/templates/marathon/fetcher-http.json"
FETCHER_HTTP_RENDERED_TEMPLATE="${WORKSPACE}/fetcher-http.json"
FETCHER_HTTPS_TEMPLATE="$DIR/templates/marathon/fetcher-https.json"
FETCHER_HTTPS_RENDERED_TEMPLATE="${WORKSPACE}/fetcher-https.json"
FETCHER_LOCAL_TEMPLATE="$DIR/templates/marathon/fetcher-local.json"
FETCHER_LOCAL_RENDERED_TEMPLATE="${WORKSPACE}/fetcher-local.json"
FETCHER_LOCAL_FILE_URL="http://dcos-win.westus.cloudapp.azure.com/dcos-windows/testing/fetcher-test.zip"
FETCHER_FILE_MD5="07d6bb2d5baed0c40396c229259caa71"
LOG_SERVER_ADDRESS="dcos-win.westus.cloudapp.azure.com"
LOG_SERVER_USER="jenkins"
REMOTE_LOGS_DIR="/data/artifacts/${JOB_NAME}"
LOGS_BASE_URL="http://dcos-win.westus.cloudapp.azure.com/artifacts/${JOB_NAME}"
UTILS_FILE="$DIR/utils/utils.sh"
BUILD_OUTPUTS_URL="$LOGS_BASE_URL/$BUILD_ID"
PARAMETERS_FILE="$WORKSPACE/build-parameters.txt"
TEMP_LOGS_DIR="$WORKSPACE/$BUILD_ID"
VENV_DIR="$WORKSPACE/venv"
JENKINS_CLI="$WORKSPACE/jenkins-cli.jar"

rm -f $PARAMETERS_FILE && touch $PARAMETERS_FILE && mkdir -p $TEMP_LOGS_DIR && source $UTILS_FILE || exit 1


azure_cli_login() {
    # Validate that credential variables are set
    if [[ -z $AZURE_SERVICE_PRINCIPAL_ID ]]; then echo "ERROR: Parameter AZURE_SERVICE_PRINCIPAL_ID is not set"; exit 1; fi
    if [[ -z $AZURE_SERVICE_PRINCIPAL_PASSWORD ]]; then echo "ERROR: Parameter AZURE_SERVICE_PRINCIPAL_PASSWORD is not set"; exit 1; fi
    if [[ -z $AZURE_SERVICE_PRINCIPAL_TENAT ]]; then echo "ERROR: Parameter AZURE_SERVICE_PRINCIPAL_TENAT is not set"; exit 1; fi
    # Check if we are already logged in
    if az account list --output json | jq -r '.[0]["user"]["name"]' | grep -q "^${AZURE_SERVICE_PRINCIPAL_ID}$"; then
        echo "Account is already logged"
        return 0
    fi
    # Login
    az login --output table --service-principal -u $AZURE_SERVICE_PRINCIPAL_ID -p $AZURE_SERVICE_PRINCIPAL_PASSWORD --tenant $AZURE_SERVICE_PRINCIPAL_TENAT || {
        echo "ERROR: Failed to login into Azure"
        return 1
    }
}

get_linux_ssh_keypair() {
    # Download private/public keys secrets from Azure key vault
    echo "Downloading ssh private keypair from key vault"
    az keyvault secret download --vault-name "$AZURE_KEYVAULT_NAME" --name "$PRIVATE_KEY_SECRET_NAME" --file "${WORKSPACE}/id_rsa.b64" || {
        echo "ERROR: Failed to download private key from Azure key vault $AZURE_KEYVAULT_NAME"
        return 1
    }
    # Decode private key
    base64 -d ${WORKSPACE}/id_rsa.b64 > ${WORKSPACE}/id_rsa || {
        echo "ERROR: Failed to decode private key"
        return 1
    }
    chmod 600 ${WORKSPACE}/id_rsa
    echo "Downloading ssh public key from key vault"
    az keyvault secret download --vault-name "$AZURE_KEYVAULT_NAME" --name "$PUBLIC_KEY_SECRET_NAME" --file "${WORKSPACE}/id_rsa.pub" || {
        echo "ERROR: Failed to download public key from Azure key vault $AZURE_KEYVAULT_NAME"
        return 1
    }
    # Export downloaded public key as variable
    export PRIVATE_SSH_KEY_PATH="${WORKSPACE}/id_rsa"
    export LINUX_PUBLIC_SSH_KEY=$(cat ${WORKSPACE}/id_rsa.pub)
}

get_windows_password() {
    echo "Downloading Windows password from key vault"
    az keyvault secret download --vault-name "$AZURE_KEYVAULT_NAME" --name "$WIN_PASS_SECRET_NAME" --file "${WORKSPACE}/win_pass" || {
        echo "ERROR: Failed to download Windows password from Azure key vault $AZURE_KEYVAULT_NAME"
        return 1
    }
    # Export downloaded password as variable
    export WIN_AGENT_ADMIN_PASSWORD=$(cat ${WORKSPACE}/win_pass)
}

copy_ssh_key_to_proxy_master() {
    #
    # Upload the authorized SSH private key to the first master. We'll use
    # this one as a proxy node to execute remote CI commands against all the
    # Linux slaves.
    #
    run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  'mkdir -p $HOME/.ssh && chmod 700 $HOME/.ssh' || {
        echo "ERROR: Failed to create remote .ssh directory"
        return 1
    }
    upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f '$HOME/.ssh/id_rsa' "$PRIVATE_SSH_KEY_PATH" || {
        echo "ERROR: Failed to copy the id_rsa private ssh key"
        return 1
    }
}

job_cleanup() {
    #
    # Deletes the Azure resource group used for the deployment
    #
    echo "Cleanup in progress for the current Azure DC/OS deployment"
    if [[ ! -z $DCOS_CLUSTER_ID ]]; then
        dcos cluster remove $DCOS_CLUSTER_ID || {
            echo "WARNING: Failed to remove the DC/OS cluster session for cluster ID: $DCOS_CLUSTER_ID"
        }
        rm -rf $DCOS_DIR || return 1
    fi
    if [[ "$SET_CLEANUP_TAG" = "true" ]]; then
        if [[ "$STATUS" = "PASS" ]]; then
            RESOURCE_GROUP_CLEANUP="true"
        else
            RESOURCE_GROUP_CLEANUP="false"
        fi
    fi
    if [[ -z $RESOURCE_GROUP_CLEANUP ]]; then
        if [[ "$AUTOCLEAN" = "true" ]]; then
            RESOURCE_GROUP_CLEANUP="true"
        else
            RESOURCE_GROUP_CLEANUP="false"
        fi
    fi
    if [[ "$RESOURCE_GROUP_CLEANUP" = "true" ]]; then
        echo "Deleting resource group: $AZURE_RESOURCE_GROUP"
        az group delete --yes --no-wait --name $AZURE_RESOURCE_GROUP --output table || {
            echo "ERROR: Failed to delete the resource group"
            return 1
        }
    fi
    echo "Finished the environment cleanup"
}

upload_logs() {
    #
    # Uploads the logs to the log server
    #
    # Copy the Jenkins console as well
    curl --user ${JENKINS_USER}:${JENKINS_PASSWORD} "${JENKINS_URL}/job/${JOB_NAME}/${BUILD_NUMBER}/consoleText" -o $TEMP_LOGS_DIR/jenkins-console.log || return 1
    echo "Uploading logs to the log server"
    run_ssh_command -u $LOG_SERVER_USER -h $LOG_SERVER_ADDRESS -p "22" -c "mkdir -p ${REMOTE_LOGS_DIR}" || return 1
    upload_files_via_scp -u $LOG_SERVER_USER -h $LOG_SERVER_ADDRESS -p "22" -f "${REMOTE_LOGS_DIR}/" $TEMP_LOGS_DIR || return 1
    echo "All the logs available at: $BUILD_OUTPUTS_URL"
    echo "BUILD_OUTPUTS_URL=$BUILD_OUTPUTS_URL" >> $PARAMETERS_FILE
    rm -rf $TEMP_LOGS_DIR || return 1
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
    MASTER_NIC_NAME=$(az network nic list --resource-group $AZURE_RESOURCE_GROUP --output table | grep 'dcos-master' | awk '{print $5}' | head -1) || {
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
                               --access Allow --protocol Tcp --direction Inbound --source-address-prefixes $MASTER_WHITELISTED_IPS \
                               --priority 100 --destination-port-range 80 --output table || {
        echo "ERROR: Failed to create the DC/OS port security group rule for the master node"
        return 1
    }
    echo "Checking, with a timeout of 900 seconds, if the port 80 is open at the address $MASTER_PUBLIC_ADDRESS"
    check_open_port "$MASTER_PUBLIC_ADDRESS" "80" "900" || return 1
    echo "Success: Port 80 is open at address $MASTER_PUBLIC_ADDRESS"
}

setup_remote_winrm_client() {
    local WSMANCMD_URL="http://dcos-win.westus.cloudapp.azure.com/downloads/wsmancmd"
    curl -s --retry 30 "${WSMANCMD_URL}" -o $WORKSPACE/wsmancmd || {
        echo "ERROR: Failed to download wsmancmd binary from ${WSMANCMD_URL}"
        return 1
    }
    chmod +x $WORKSPACE/wsmancmd
    upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f "/tmp/wsmancmd" "$WORKSPACE/wsmancmd" || {
        echo "ERROR: Failed to copy wsmancmd binary to the proxy master node"
        return 1
    }
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

get_marathon_application_host_port() {
    local TEMPLATE_PATH="$1"
    cat $TEMPLATE_PATH | python -c "import json,sys ; input = json.load(sys.stdin) ; print(input['container']['docker']['portMappings'][0]['hostPort'])"
}

test_dcos_task_connectivity() {
    #
    # Test connectivity against a dcos tasks
    #
    local APP_NAME=$1
    local AGENT_HOSTNAME=$2
    local AGENT_ROLE=$3
    local PORT=$4
    local TIMEOUT="900"
    # Check port depending on agent role
    if [[ "$AGENT_ROLE" == "slave_public" ]]; then
        echo "Checking, with a timeout of $TIMEOUT seconds, if the port $PORT is open at the address: $WIN_AGENT_PUBLIC_ADDRESS"
        check_open_port "$WIN_AGENT_PUBLIC_ADDRESS" "$PORT" "$TIMEOUT" || {
            echo "ERROR: Port $PORT is not open for the application: $APP_NAME"
            dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
            return 1
        }
        echo "Success: Port $PORT is open at address $WIN_AGENT_PUBLIC_ADDRESS"
    else
        echo "Checking, with a timeout of $TIMEOUT seconds, if the port $PORT is open at the address: $AGENT_HOSTNAME"
        upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f "/tmp/utils.sh" "$DIR/utils/utils.sh" || {
            echo "ERROR: Failed to scp utils.sh"
            return 1
        }
        run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "source /tmp/utils.sh && check_open_port $AGENT_HOSTNAME $PORT $TIMEOUT" || {
            echo "ERROR: Port $PORT is not open for the application: $APP_NAME"
            dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
            return 1
        }
        echo "Success: Port $PORT is open at address $AGENT_HOSTNAME"
    fi
}

test_win_marathon_app_port_container() {
    #
    # - Deploy a simple web server on Windows
    # - Check if Marathon successfully launched the Mesos Docker task
    # - Check if the exposed port is open
    # - Check if the DNS records for the task are advertised to the Windows nodes
    #
    local AGENT_HOSTNAME=$1
    local AGENT_ROLE=$2
    local APP_ID="test-win-app-container-$(echo $AGENT_HOSTNAME | tr . -)"
    # Generate json file from template
	eval "cat <<-EOF
	$(cat $WINDOWS_APP_CONTAINER_TEMPLATE)
	EOF
	" > $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE
    # Start deployment
    echo "Deploying a Windows Marathon application on DC/OS"
    dcos marathon app add $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE || {
        echo "ERROR: Failed to deploy the Windows Marathon application"
        return 1
    }
    APP_NAME=$(get_marathon_application_name $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE)
    $DIR/utils/check-marathon-app-health.py --name $APP_NAME || {
        echo "ERROR: Failed to get $APP_NAME application health checks"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }
    PORT=$(get_marathon_application_host_port $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE)
    test_dcos_task_connectivity "$APP_NAME" "$AGENT_HOSTNAME" "$AGENT_ROLE" "$PORT" || return 1
    setup_remote_winrm_client || return 1
    TASK_HOST=$(dcos marathon app show $APP_NAME | jq -r ".tasks[0].host")
    DNS_RECORDS=(
        "${APP_NAME}.marathon.agentip.dcos.thisdcos.directory"
        "${APP_NAME}.marathon.autoip.dcos.thisdcos.directory"
        "${APP_NAME}.marathon.containerip.dcos.thisdcos.directory"
        "${APP_NAME}.marathon.mesos.thisdcos.directory"
        "${APP_NAME}.marathon.slave.mesos.thisdcos.directory"
    )
    for DNS_RECORD in ${DNS_RECORDS[@]}; do
        test_windows_agent_dcos_dns "$TASK_HOST" "$DNS_RECORD" || return 1
    done
    echo "Windows Marathon application successfully deployed on DC/OS"
    dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
    remove_dcos_marathon_app $APP_NAME || return 1
}

test_win_marathon_app_port_publish() {
    #
    # - Deploy a simple DC/OS marathon application
    #
    local AGENT_HOSTNAME=$1
    local AGENT_ROLE=$2
    local APP_ID="test-win-app-publish-$(echo $AGENT_HOSTNAME | tr . -)"
    # Generate json file from template
	eval "cat <<-EOF
	$(cat $WINDOWS_APP_PUBLISH_TEMPLATE)
	EOF
	" > $WINDOWS_APP_PUBLISH_RENDERED_TEMPLATE
    # Start deployment
    echo "Deploying Windows application on DC/OS"
    dcos marathon app add $WINDOWS_APP_PUBLISH_RENDERED_TEMPLATE || {
        echo "ERROR: Failed to deploy the Windows Marathon application"
        return 1
    }
    APP_NAME=$(get_marathon_application_name $WINDOWS_APP_PUBLISH_RENDERED_TEMPLATE)
    $DIR/utils/check-marathon-app-health.py --name $APP_NAME || {
        echo "ERROR: Failed to get $APP_NAME application health checks"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }
    PORT="80"
    test_dcos_task_connectivity "$APP_NAME" "$AGENT_HOSTNAME" "$AGENT_ROLE" "$PORT" || return 1
    dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
    remove_dcos_marathon_app $APP_NAME || return 1
}

test_docker_private_image() {
    #
    # Check if marathon can spawn a simple DC/OS Windows marathon application from a private docker image
    #
    local AGENT_HOSTNAME=$1
    local AGENT_ROLE=$2
    local APP_ID="test-docker-private-$(echo $AGENT_HOSTNAME | tr . -)"
    
    # Generate json file from template
	eval "cat <<-EOF
	$(cat $DOCKER_PRIVATE_TEMPLATE)
	EOF
	" > $DOCKER_PRIVATE_RENDERED_TEMPLATE

    # Start deployment
    echo "Testing marathon applications with Docker private images"

    # Login to create the docker config file with credentials
    echo $DOCKER_HUB_USER_PASSWORD | docker --config $WORKSPACE/.docker/ login -u $DOCKER_HUB_USER --password-stdin || return 1

    # Create the zip archive
    pushd $WORKSPACE && zip -r docker.zip .docker && rm -rf .docker && popd || return 1

    # Upload docker.zip to master
    upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f "/tmp/docker.zip" "$WORKSPACE/docker.zip" || {
        echo "ERROR: Failed to scp docker.zip"
        return 1
    }

    rm $WORKSPACE/docker.zip || {
        echo "ERROR: Failed to clean up docker.zip"
        return 1
    }

    upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f "/tmp/utils.sh" "$DIR/utils/utils.sh" || {
        echo "ERROR: Failed to scp utils.sh"
        return 1
    }

    # Download the config file with creds locally to targeted node
    run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "source /tmp/utils.sh && mount_smb_share $AGENT_HOSTNAME $WIN_AGENT_ADMIN $WIN_AGENT_ADMIN_PASSWORD && sudo cp /tmp/docker.zip /mnt/$AGENT_HOSTNAME/docker.zip" || {
        echo "ERROR: Failed to copy the fetcher resource file to Windows public agent $IP"
        return 1
    }

    echo "Deploying Windows application from private image on DC/OS"
    dcos marathon app add $DOCKER_PRIVATE_RENDERED_TEMPLATE || {
        echo "ERROR: Failed to deploy the Windows Marathon application from private image"
        return 1
    }
    APP_NAME=$(get_marathon_application_name $DOCKER_PRIVATE_RENDERED_TEMPLATE)
    $DIR/utils/check-marathon-app-health.py --name $APP_NAME || {
        echo "ERROR: Failed to get $APP_NAME application health checks"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }
    PORT="80"
    test_dcos_task_connectivity "$APP_NAME" "$AGENT_HOSTNAME" "$AGENT_ROLE" "$PORT" || return 1
    dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
    remove_dcos_marathon_app $APP_NAME || return 1
    echo "Successfully tested marathon applications with Docker private images"
}

test_custom_attributes() {
    #
    # Check if the custom attributes are set for the slaves
    #
    $DIR/utils/check-custom-attributes.py || return 1
    echo "The custom attributes are correctly set"
}

test_mesos_fetcher() {
    local APPLICATION_NAME="$1"
    local AGENT_HOSTNAME="$2"
    $DIR/utils/check-marathon-app-health.py --name $APPLICATION_NAME || return 1
    setup_remote_winrm_client || return 1
    upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f "/tmp/mesos-fetcher-checksum.ps1" "$DIR/utils/mesos-fetcher-checksum.ps1" || {
        echo "ERROR: Failed to scp mesos-fetcher-checksum.ps1"
        return 1
    }
    MD5_CHECKSUM=$(run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "/tmp/wsmancmd -H $AGENT_HOSTNAME -s -a basic -u $WIN_AGENT_ADMIN -p $WIN_AGENT_ADMIN_PASSWORD --powershell --file /tmp/mesos-fetcher-checksum.ps1") || {
        echo "ERROR: Failed to get MD5 checksum for the fetcher file"
    }
    if [[ "$MD5_CHECKSUM" != "$FETCHER_FILE_MD5" ]]; then
        echo "ERROR: Fetcher file MD5 checksum is not correct. The checksum found is $MD5_CHECKSUM and the expected one is $FETCHER_FILE_MD5"
        return 1
    fi
    echo -e "\n"
    echo -e "The MD5 checksum for the fetcher file was successfully checked"
    echo -e "\n"
}

test_mesos_fetcher_local() {
    #
    # Test Mesos fetcher with local resource
    #
    local AGENT_HOSTNAME=$1
    local AGENT_ROLE=$2
    local APP_ID="test-fetcher-local-$(echo $AGENT_HOSTNAME | tr . -)"
    # Generate json file from template
	eval "cat <<-EOF
	$(cat $FETCHER_LOCAL_TEMPLATE)
	EOF
	" > $FETCHER_LOCAL_RENDERED_TEMPLATE
    # Start deployment
    echo "Testing Mesos fetcher using local resource"
    upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f "/tmp/utils.sh" "$DIR/utils/utils.sh" || {
        echo "ERROR: Failed to scp utils.sh"
        return 1
    }
    # Download the fetcher test file locally to targeted node
    run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "source /tmp/utils.sh && mount_smb_share $AGENT_HOSTNAME $WIN_AGENT_ADMIN $WIN_AGENT_ADMIN_PASSWORD && sudo wget $FETCHER_LOCAL_FILE_URL -O /mnt/$AGENT_HOSTNAME/fetcher-test.zip" || {
        echo "ERROR: Failed to copy the fetcher resource file to Windows public agent $IP"
        return 1
    }
    dcos marathon app add $FETCHER_LOCAL_RENDERED_TEMPLATE || return 1
    APP_NAME=$(get_marathon_application_name $FETCHER_LOCAL_RENDERED_TEMPLATE)
    test_mesos_fetcher $APP_NAME $AGENT_HOSTNAME || {
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
    local AGENT_HOSTNAME=$1
    local AGENT_ROLE=$2
    local APP_ID="test-fetcher-http-$(echo $AGENT_HOSTNAME | tr . -)"
    # Generate json file from template
	eval "cat <<-EOF
	$(cat $FETCHER_HTTP_TEMPLATE)
	EOF
	" > $FETCHER_HTTP_RENDERED_TEMPLATE
    # Start deployment
    echo "Testing Mesos fetcher using remote http resource"
    dcos marathon app add $FETCHER_HTTP_RENDERED_TEMPLATE || return 1
    APP_NAME=$(get_marathon_application_name $FETCHER_HTTP_RENDERED_TEMPLATE)
    test_mesos_fetcher $APP_NAME $AGENT_HOSTNAME || {
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
    local AGENT_HOSTNAME=$1
    local AGENT_ROLE=$2
    local APP_ID="test-fetcher-https-$(echo $AGENT_HOSTNAME | tr . -)"
    # Generate json file from template
	eval "cat <<-EOF
	$(cat $FETCHER_HTTPS_TEMPLATE)
	EOF
	" > $FETCHER_HTTPS_RENDERED_TEMPLATE
    # Start deployment
    echo "Testing Mesos fetcher using remote https resource"
    dcos marathon app add $FETCHER_HTTPS_RENDERED_TEMPLATE || return 1
    APP_NAME=$(get_marathon_application_name $FETCHER_HTTPS_RENDERED_TEMPLATE)
    test_mesos_fetcher $APP_NAME $AGENT_HOSTNAME || {
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
    local DNS_RECORD="$2"
    echo -e "Trying to resolve $DNS_RECORD on Windows agent $AGENT_IP"
    REMOTE_CMD="/tmp/wsmancmd -H $AGENT_IP -s -a basic -u $WIN_AGENT_ADMIN -p $WIN_AGENT_ADMIN_PASSWORD --powershell 'nslookup.exe $DNS_RECORD' >/tmp/winrm.stdout 2>/tmp/winrm.stderr"
    MAX_RETRIES=10
    RETRIES=0
    while [[ $RETRIES -le $MAX_RETRIES ]]; do
        run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "$REMOTE_CMD" || {
            echo -e "WARNING: Failed to resolve $DNS_RECORD"
            RETRIES=$(($RETRIES + 1))
            continue
        }
        run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "cat /tmp/winrm.stdout"
        echo ""
        echo "Successfully resolved $DNS_RECORD"
        return 0
    done
    echo "ERROR: Failed to resolve $DNS_RECORD"
    run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "cat /tmp/winrm.stdout ; cat /tmp/winrm.stderr"
    echo ""
    return 1
}

test_dcos_dns() {
    #
    # Tries to resolve 'leader.mesos' and 'master.masos' from all the Windows
    # slaves. A remote PowerShell command is executed via WinRM. This ensures
    # that the DC/OS dns component on Windows (Spartan or dcos-net) is correctly
    # set up
    #
    echo "Testing DC/OS DNS on the Windows slaves"
    setup_remote_winrm_client || return 1
    if [[ $WIN_PRIVATE_AGENT_COUNT -gt 0 ]]; then
        IPS=$($DIR/utils/dcos-node-addresses.py --operating-system 'windows' --role 'private') || return 1
        for IP in $IPS; do
            echo "Checking DNS for Windows private agent: $IP"
            for DNS_RECORD in microsoft.com leader.mesos master.mesos; do
                test_windows_agent_dcos_dns "$IP" "$DNS_RECORD" || return 1
            done
        done
    fi
    if [[ $WIN_PUBLIC_AGENT_COUNT -gt 0 ]]; then
        IPS=$($DIR/utils/dcos-node-addresses.py --operating-system 'windows' --role 'public') || return 1
        for IP in $IPS; do
            echo "Checking DNS for Windows public agent: $IP"
            for DNS_RECORD in microsoft.com leader.mesos master.mesos; do
                test_windows_agent_dcos_dns "$IP" "$DNS_RECORD" || return 1
            done
        done
    fi
}

test_master_agent_authentication() {
    PYTHON_SCRIPT="import json,sys; input = json.load(sys.stdin); print(input['flags']['authenticate_agents'])"
    for i in `seq 0 $(($LINUX_MASTER_COUNT - 1))`; do
        MASTER_SSH_PORT="220$i"
        AUTH_ENABLED=$(run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p $MASTER_SSH_PORT -c "curl -s http://\$(/opt/mesosphere/bin/detect_ip):5050/flags | python -c \"${PYTHON_SCRIPT}\"") || {
            echo "ERROR: Failed to find the Mesos flags on the master $i"
            return 1
        }
        if [[ "$AUTH_ENABLED" != "true" ]]; then
            echo "ERROR: Master $i doesn't have 'authenticate_agents' flag enabled"
            return 1
        fi
    done
    echo "Success: All the masters have the authenticate_agents flag enabled"
}

compare_azure_vms_and_dcos_agents() {
    # Get list of all agent IPs by concatenating output of win and linux functions
    local agent_ips="$(echo $(linux_agents_private_ips) $(windows_agents_private_ips) | tr ' ' '\n' | sort)"

    # Count number of Azure IPs
    local agent_ips_no=$(echo $agent_ips | tr ' ' '\n' | awk 'END{print NR}')

    # Fetch API agent IPs list
    local dcos_api_ips=$(dcos node | grep agent | awk '{print $2}' | sort) || {
        echo "ERROR: Failed to run 'dcos node'"
        return 1
    }
    # Count API agent IPs
    local dcos_api_ips_no=$(echo $dcos_api_ips | tr ' ' '\n' | awk 'END{print NR}')

    # Compare number of IPs, return 1 if not equal
    if [ $agent_ips_no -ne $dcos_api_ips_no ]; then
        echo "ERROR: Number of Azure VM IPs is different from number of DCOS API IPs"
        return 1
    fi
    # diff the 2 lists of IPs (which are already sorted)
    diff -bB <(echo "$agent_ips") <(echo "$dcos_api_ips") 2>&1

    # If previous command has exit_code=0 then the lists are different and we return 1
    if [ $? -eq 1 ]; then
        echo "ERROR: Some Azure VM IPs are different from DCOS API IPs"
        return 1
    elif [ $? -gt 1 ]; then
        echo "ERROR: diff encountered an error"
        return 1
    fi
}

test_dcos_windows_apps() {
    #
    # Test DC/OS apps on all available Windows nodes
    #
    # Get the IPs of all Windows agents
    local WIN_PRIVATE_AGENTS_IPS=$($DIR/utils/dcos-node-addresses.py --operating-system 'windows' --role 'private') || return 1
    local WIN_PUBLIC_AGENTS_IPS=$($DIR/utils/dcos-node-addresses.py --operating-system 'windows' --role 'public') || return 1
    if [[ -z $WIN_PRIVATE_AGENTS_IPS ]] && [[ -z $WIN_PUBLIC_AGENTS_IPS ]]; then
        echo "ERROR: No Windows slaves registered"
        return 1
    fi
    for PRIVATE_AGENT_IP in $WIN_PRIVATE_AGENTS_IPS; do
        local AGENT_ROLE="*"
        test_win_marathon_app_port_container "$PRIVATE_AGENT_IP" "$AGENT_ROLE" || return 1
        test_win_marathon_app_port_publish "$PRIVATE_AGENT_IP" "$AGENT_ROLE" || return 1
        test_windows_agent_recovery "$PRIVATE_AGENT_IP" "$AGENT_ROLE" || return 1
        test_docker_private_image "$PRIVATE_AGENT_IP" "$AGENT_ROLE" || return 1
        test_mesos_fetcher_local "$PRIVATE_AGENT_IP" "$AGENT_ROLE" || return 1
        test_mesos_fetcher_remote_http "$PRIVATE_AGENT_IP" "$AGENT_ROLE" || return 1
        test_mesos_fetcher_remote_https "$PRIVATE_AGENT_IP" "$AGENT_ROLE" || return 1
    done
    for PUBLIC_AGENT_IP in $WIN_PUBLIC_AGENTS_IPS; do
        local AGENT_ROLE="slave_public"
        test_win_marathon_app_port_container "$PUBLIC_AGENT_IP" "$AGENT_ROLE" || return 1
        test_win_marathon_app_port_publish "$PUBLIC_AGENT_IP" "$AGENT_ROLE" || return 1
        test_windows_agent_recovery "$PUBLIC_AGENT_IP" "$AGENT_ROLE" || return 1
        test_docker_private_image "$PUBLIC_AGENT_IP" "$AGENT_ROLE" || return 1
        test_mesos_fetcher_local "$PUBLIC_AGENT_IP" "$AGENT_ROLE" || return 1
        test_mesos_fetcher_remote_http "$PUBLIC_AGENT_IP" "$AGENT_ROLE" || return 1
        test_mesos_fetcher_remote_https "$PUBLIC_AGENT_IP" "$AGENT_ROLE" || return 1
    done

    # Shutdown testing
    local AGENT_ROLES=("*" "slave_public")
    for ROLE in "${AGENT_ROLES[@]}"; do
        test_windows_agent_graceful_shutdown "${ROLE}" || return 1
        test_windows_agent_ungraceful_shutdown "${ROLE}" || return 1
    done
    
    # Resiliency testing
    test_windows_agent_resiliency || return 1
}

test_windows_agent_recovery() {
    #
    #### Deploy test app and run health check
    #
    local AGENT_HOSTNAME=$1
    local AGENT_ROLE="$2"
    local APP_ID="test-windows-recovery-$(echo $AGENT_HOSTNAME | tr . -)"
    eval "cat <<-EOF
	$(cat $WINDOWS_APP_CONTAINER_TEMPLATE)
	EOF
	" > $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE
    echo "Deploying a Windows Marathon application on DC/OS"

    dcos marathon app add $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE || {
        echo "ERROR: Failed to deploy the Windows Marathon application"
        return 1
    }
    
    local APP_NAME=$(get_marathon_application_name $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE)
    
    $DIR/utils/check-marathon-app-health.py --name $APP_NAME || {
        echo "ERROR: Failed to get $APP_NAME application health checks"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }

    local PORT=$(get_marathon_application_host_port $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE)
    test_dcos_task_connectivity "$APP_NAME" "$AGENT_HOSTNAME" "$AGENT_ROLE" "$PORT" || return 1

    #
    #### Recovery checks
    #
    setup_remote_winrm_client || return 1
    upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f "/tmp/kill-mesos-agent.ps1" "$DIR/utils/kill-mesos-agent.ps1" || {
        echo "ERROR: Failed to scp kill-mesos-agent.ps1"
        return 1
    }
    echo "Killing mesos-agent.exe on $AGENT_HOSTNAME and waiting for the service to restart"
    local REMOTE_CMD_KILL="/tmp/wsmancmd -H $AGENT_HOSTNAME -s -a basic -u $WIN_AGENT_ADMIN -p $WIN_AGENT_ADMIN_PASSWORD --powershell --file /tmp/kill-mesos-agent.ps1"
    local CHECK_RESULT=$(run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c "$REMOTE_CMD_KILL" 2>/dev/null) || {
        echo -e "Error: Failed to run service kill script on $AGENT_HOSTNAME"
        return 1
    }

    if [ "$CHECK_RESULT" == "SUCCESS" ]; then
        echo "Service dcos-mesos-slave successfully restarted!"
    elif [ "$CHECK_RESULT" == "FAILURE" ]; then
        echo "ERROR: Service dcos-mesos-slave restart failure"
        return 1
    else
        echo "ERROR: $CHECK_RESULT"
        return 1
    fi


    local TASK_HOSTNAME=$(dcos marathon app show $APP_NAME | jq -r ".tasks[0].host")
    if [[ $TASK_HOSTNAME == $AGENT_HOSTNAME ]]; then
        echo "Task still running on $AGENT_HOSTNAME"
    else
        echo "Task not running on $AGENT_HOSTNAME"
        return 1
    fi
    # Check task health after service restart
    $DIR/utils/check-marathon-app-health.py --name $APP_NAME || {
        echo "ERROR: Failed to get $APP_NAME application health checks"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }

    test_dcos_task_connectivity "$APP_NAME" "$AGENT_HOSTNAME" "$AGENT_ROLE" "$PORT" || return 1

    echo "Recovery successful on $AGENT_HOSTNAME!"

    remove_dcos_marathon_app $APP_NAME || return 1
}

test_windows_agent_graceful_shutdown() {
    local AGENT_ROLE="$1"
    if [[ "${AGENT_ROLE}" == "*" ]]; then
        local APP_ID="test-windows-graceful-shutdown-private-agent"
    else
        local APP_ID="test-windows-graceful-shutdown-public-agent"
    fi
    # eval-ing template and deleting hostname constraint -- failover impossible with constraint
    eval "cat <<-EOF
	$(cat $WINDOWS_APP_CONTAINER_TEMPLATE | jq -r 'del(.constraints[1])')
	EOF
	" > $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE

    echo "Deploying a Windows Marathon application on DC/OS"

    dcos marathon app add $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE || {
        echo "ERROR: Failed to deploy the Windows Marathon application"
        return 1
    }
    
    local APP_NAME=$(get_marathon_application_name $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE)
    
    $DIR/utils/check-marathon-app-health.py --name $APP_NAME || {
        echo "ERROR: Failed to get $APP_NAME application health checks"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }
    local PORT=$(get_marathon_application_host_port $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE)
    local AGENT_HOSTNAME=$(dcos marathon app show $APP_NAME | jq -r ".tasks[0].host")
    test_dcos_task_connectivity "$APP_NAME" "$AGENT_HOSTNAME" "$AGENT_ROLE" "$PORT" || return 1
    
    #
    #### Stopping service
    #
    setup_remote_winrm_client || return 1
    upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f "/tmp/stop-mesos-service.ps1" "$DIR/utils/stop-mesos-service.ps1" || {
        echo "ERROR: Failed to scp stop-mesos-service.ps1"
        return 1
    }
    echo "Stopping the dcos-mesos-slave service on $AGENT_HOSTNAME"
    local REMOTE_CMD_STOP="/tmp/wsmancmd -H $AGENT_HOSTNAME -s -a basic -u $WIN_AGENT_ADMIN -p $WIN_AGENT_ADMIN_PASSWORD --powershell --file /tmp/stop-mesos-service.ps1"
    local CHECK_RESULT_STOP=$(run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c "$REMOTE_CMD_STOP" 2>/dev/null) || {
        echo -e "Error: Failed to run service kill script on $AGENT_HOSTNAME"
        return 1
    }

    if [ "$CHECK_RESULT_STOP" == "SUCCESS" ]; then
        echo "Service dcos-mesos-slave successfully Stopped!"
    elif [ "$CHECK_RESULT_STOP" == "FAILURE" ]; then
        echo "ERROR: Service dcos-mesos-slave stopping failure"
        return 1
    else
        echo "ERROR: Service dcos-mesos-slave is in '$CHECK_RESULT' state, which is unknown"
        return 1
    fi

    echo "Waiting with a timeout of 3mins for DCOS to migrate the task from $AGENT_HOSTNAME..."
    local NEW_TASK_HOST=""
    SECONDS=0
    while true; do
        if [[ $SECONDS -gt 180 ]]; then
            echo "ERROR: task for $APP_NAME didn't migrate from $AGENT_HOSTNAME within $TIMEOUT seconds"
            return 1
        fi
        NEW_TASK_HOST=$(dcos marathon app show $APP_NAME | jq -r ".tasks[0].host")
        if [[ $NEW_TASK_HOST != $AGENT_HOSTNAME ]] && [[ ! -z $NEW_TASK_HOST ]] && [[ $NEW_TASK_HOST != "null" ]]; then
            echo "Task successfully migrated from $AGENT_HOSTNAME to $NEW_TASK_HOST"    
            break
        else
            sleep 1
        fi

    done

    # Check task health after task failover
    $DIR/utils/check-marathon-app-health.py --name $APP_NAME --ignore-last-task-failure || {
        echo "ERROR: Failed to get $APP_NAME application health checks"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }
    test_dcos_task_connectivity "$APP_NAME" "$NEW_TASK_HOST" "$AGENT_ROLE" "$PORT" || return 1
    echo "Graceful shutdown successful on $AGENT_HOSTNAME!"

    remove_dcos_marathon_app $APP_NAME || return 1
    
    # Start service back up
    upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f "/tmp/start-mesos-service.ps1" "$DIR/utils/start-mesos-service.ps1" || {
        echo "ERROR: Failed to scp start-mesos-service.ps1"
        return 1
    }
    local REMOTE_CMD_START="/tmp/wsmancmd -H $AGENT_HOSTNAME -s -a basic -u $WIN_AGENT_ADMIN -p $WIN_AGENT_ADMIN_PASSWORD --powershell --file /tmp/start-mesos-service.ps1"
    local CHECK_RESULT_START=$(run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c "$REMOTE_CMD_START" 2>/dev/null) || {
        echo -e "Error: Failed to run service start script on $AGENT_HOSTNAME"
        return 1
    }

    if [ "$CHECK_RESULT_START" == "SUCCESS" ]; then
        echo "Service dcos-mesos-slave successfully started back up!"
    elif [ "$CHECK_RESULT_START" == "FAILURE" ]; then
        echo "ERROR: Service dcos-mesos-slave starting failure"
        return 1
    else
        echo "ERROR: Service dcos-mesos-slave is in '$CHECK_RESULT' state, which is unknown"
        return 1
    fi
}

test_windows_agent_ungraceful_shutdown() {
    local AGENT_ROLE="$1"
    if [[ "${AGENT_ROLE}" == "*" ]]; then
        local APP_ID="test-windows-ungraceful-shutdown-private-agent"
    else
        local APP_ID="test-windows-ungraceful-shutdown-public-agent"
    fi
    # eval-ing template and deleting hostname constraint -- failover impossible with constraint
    eval "cat <<-EOF
	$(cat $WINDOWS_APP_CONTAINER_TEMPLATE | jq -r 'del(.constraints[1])')
	EOF
	" > $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE

    echo "Deploying a Windows Marathon application on DC/OS"

    dcos marathon app add $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE || {
        echo "ERROR: Failed to deploy the Windows Marathon application"
        return 1
    }
    
    local APP_NAME=$(get_marathon_application_name $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE)
    
    $DIR/utils/check-marathon-app-health.py --name $APP_NAME || {
        echo "ERROR: Failed to get $APP_NAME application health checks"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }
    local PORT=$(get_marathon_application_host_port $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE)
    local AGENT_HOSTNAME=$(dcos marathon app show $APP_NAME | jq -r ".tasks[0].host")
    test_dcos_task_connectivity "$APP_NAME" "$AGENT_HOSTNAME" "$AGENT_ROLE" "$PORT" || return 1
    
    #
    #### Killing the service
    #
    setup_remote_winrm_client || return 1
    upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f "/tmp/kill-mesos-agent-ungraceful.ps1" "$DIR/utils/kill-mesos-agent-ungraceful.ps1" || {
        echo "ERROR: Failed to scp kill-mesos-agent-ungraceful.ps1"
        return 1
    }
    echo "Killing the dcos-mesos-slave service on $AGENT_HOSTNAME and disabling recovery options"
    local REMOTE_CMD_STOP="/tmp/wsmancmd -H $AGENT_HOSTNAME -s -a basic -u $WIN_AGENT_ADMIN -p $WIN_AGENT_ADMIN_PASSWORD --powershell --file /tmp/kill-mesos-agent-ungraceful.ps1"
    local CHECK_RESULT_STOP=$(run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c "$REMOTE_CMD_STOP" 2>/dev/null) || {
        echo -e "Error: Failed to run service kill script on $AGENT_HOSTNAME"
        return 1
    }

    if [ "$CHECK_RESULT_STOP" == "SUCCESS" ]; then
        echo "Service dcos-mesos-slave successfully Stopped!"
    elif [ "$CHECK_RESULT_STOP" == "FAILURE" ]; then
        echo "ERROR: Service dcos-mesos-slave stopping failure"
        return 1
    else
        echo "ERROR: Service dcos-mesos-slave is in '$CHECK_RESULT' state, which is unknown"
        return 1
    fi

    echo "Waiting with a timeout of 5mins for DCOS to fail the task over from $AGENT_HOSTNAME..."
    local NEW_TASK_HOST=""
    SECONDS=0
    while true; do
        if [[ $SECONDS -gt 300 ]]; then
            echo "ERROR: task for $APP_NAME didn't migrate from $AGENT_HOSTNAME within $TIMEOUT seconds"
            return 1
        fi
        NEW_TASK_HOST=$(dcos marathon app show $APP_NAME | jq -r ".tasks[0].host")
        if [[ $NEW_TASK_HOST != $AGENT_HOSTNAME ]] && [[ ! -z $NEW_TASK_HOST ]] && [[ $NEW_TASK_HOST != "null" ]]; then
            echo "Task successfully fail-overed from $AGENT_HOSTNAME to $NEW_TASK_HOST"    
            break
        fi
        sleep 1
    done

    # Check task health after task failover
    $DIR/utils/check-marathon-app-health.py --name $APP_NAME --ignore-last-task-failure || {
        echo "ERROR: Failed to get $APP_NAME application health checks"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }
    test_dcos_task_connectivity "$APP_NAME" "$NEW_TASK_HOST" "$AGENT_ROLE" "$PORT" || return 1

    remove_dcos_marathon_app $APP_NAME || return 1
    
    # Start service back up on old host
    upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f "/tmp/start-mesos-service.ps1" "$DIR/utils/start-mesos-service.ps1" || {
        echo "ERROR: Failed to scp start-mesos-service.ps1"
        return 1
    }
    local REMOTE_CMD_START="/tmp/wsmancmd -H $AGENT_HOSTNAME -s -a basic -u $WIN_AGENT_ADMIN -p $WIN_AGENT_ADMIN_PASSWORD --powershell --file /tmp/start-mesos-service.ps1"
    local CHECK_RESULT_START=$(run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c "$REMOTE_CMD_START" 2>/dev/null) || {
        echo -e "Error: Failed to run service start script on $AGENT_HOSTNAME"
        return 1
    }

    if [ "$CHECK_RESULT_START" == "SUCCESS" ]; then
        echo "Service dcos-mesos-slave successfully started back up on $AGENT_HOSTNAME!"
    elif [ "$CHECK_RESULT_START" == "FAILURE" ]; then
        echo "ERROR: Service dcos-mesos-slave starting failure"
        return 1
    else
        echo "ERROR: Service dcos-mesos-slave is in '$CHECK_RESULT' state, which is unknown"
        return 1
    fi

    local TASKS=$(dcos marathon task list | grep $AGENT_HOSTNAME)
    if [[ $TASKS == "" ]]; then
        echo "Ungraceful shutdown and task failover is successful on $AGENT_HOSTNAME!"
    else
        echo "ERROR: Tasks still active on $AGENT_HOSTNAME"
        return 1
    fi

}

test_windows_agent_resiliency() {
    local AGENT_ROLE="slave_public"
    local APP_ID="test-windows-resiliency-public-agent"

    # eval-ing template and deleting hostname constraint, also set instances number to number of public windows agents
    eval "cat <<-EOF
	$(cat $WINDOWS_APP_CONTAINER_TEMPLATE | jq -r 'del(.constraints[1])' | jq -r ".instances = $WIN_PUBLIC_AGENT_COUNT")
	EOF
	" > $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE

    echo "Deploying a Windows Marathon application on DC/OS"

    dcos marathon app add $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE || {
        echo "ERROR: Failed to deploy the Windows Marathon application"
        return 1
    }
    
    local APP_NAME=$(get_marathon_application_name $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE)
    
    $DIR/utils/check-marathon-app-health.py --name $APP_NAME || {
        echo "ERROR: Failed to get $APP_NAME application health checks"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }
    local PORT=$(get_marathon_application_host_port $WINDOWS_APP_CONTAINER_RENDERED_TEMPLATE)
    local AGENT_HOSTNAME=$(dcos marathon app show $APP_NAME | jq -r ".tasks[0].host")
    test_dcos_task_connectivity "$APP_NAME" "$WIN_AGENT_PUBLIC_ADDRESS" "slave_public" "$PORT" || return 1
    
    #
    #### Killing the tasks
    #

    local TASK_IDS=$(dcos marathon task list | grep $APP_NAME | awk '{print$5}')
    for TASK_ID in $TASK_IDS; do
        dcos marathon task kill "$TASK_ID"
    done

    $DIR/utils/check-marathon-app-health.py --name $APP_NAME || {
        echo "ERROR: Failed to get $APP_NAME application health checks"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }
    test_dcos_task_connectivity "$APP_NAME" "$WIN_AGENT_PUBLIC_ADDRESS" "slave_public" "$PORT" || return 1
    echo "Resiliency testing successful for Windows public nodes!"

    remove_dcos_marathon_app $APP_NAME || return 1
}

test_iis() {
    #
    # - Deploy a simple DC/OS IIS marathon application
    #
    echo "Deploying IIS application on DC/OS"
    dcos marathon app add $IIS_TEMPLATE || {
        echo "ERROR: Failed to deploy the IIS Marathon application"
        return 1
    }
    APP_NAME=$(get_marathon_application_name $IIS_TEMPLATE)
    $DIR/utils/check-marathon-app-health.py --name $APP_NAME || {
        echo "ERROR: Failed to get $APP_NAME application health checks"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }
    echo "Checking, with a timeout of 900 seconds, if the port 80 is open at the address: $WIN_AGENT_PUBLIC_ADDRESS"
    check_open_port "$WIN_AGENT_PUBLIC_ADDRESS" "80" "900" || {
        echo "ERROR: Port 80 is not open for the application: $APP_NAME"
        dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
        return 1
    }
    echo "Success: Port 80 is open at address $WIN_AGENT_PUBLIC_ADDRESS"
    dcos marathon app show $APP_NAME > "${TEMP_LOGS_DIR}/dcos-marathon-${APP_NAME}-app-details.json"
    remove_dcos_marathon_app $APP_NAME || return 1
}

run_functional_tests() {
    #
    # Run the following DC/OS functional tests:
    #  - Compare Azure VM IPs with DCOS IPs
    #  - Test if the custom attributes are set
    #  - Test if the Mesos master - agent authentication is enabled
    #  - Test DC/OS DNS functionality from the Windows node
    #  - Test a DC/OS Windows task with IIS web server
    #  - Test if a Windows marathon application can be successfully deployed and consumed
    #  - Test Windows agent recovery after taskkill
    #  - Test a simple marathon Windows app
    #  - Test Mesos fetcher with local resource
    #  - Test Mesos fetcher with remote http resource
    #  - Test Mesos fetcher with remote https resource
    #
    compare_azure_vms_and_dcos_agents || return 1
    test_custom_attributes || return 1
    test_master_agent_authentication || return 1
    test_dcos_dns || return 1
    test_iis || return 1
    test_dcos_windows_apps || return 1
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
        upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p $MASTER_SSH_PORT -f "/tmp/collect-logs.sh" $COLLECT_LINUX_LOGS_SCRIPT || return 1
        run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p $MASTER_SSH_PORT -c  "/tmp/collect-logs.sh $TMP_LOGS_DIR" || return 1
        download_files_via_scp -i $PRIVATE_SSH_KEY_PATH -h $MASTER_PUBLIC_ADDRESS -p $MASTER_SSH_PORT -f $TMP_LOGS_DIR "${LOCAL_LOGS_DIR}/" || return 1
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
    upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f "/tmp/collect-logs.sh" "$DIR/utils/collect-linux-machine-logs.sh" || return 1
    upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f "/tmp/utils.sh" "$DIR/utils/utils.sh" || return 1
    for IP in $AGENTS_IPS; do
        run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "source /tmp/utils.sh && upload_files_via_scp -u $LINUX_ADMIN -h $IP -p 22 -f /tmp/collect-logs.sh /tmp/collect-logs.sh" || return 1
        AGENT_LOGS_DIR="/tmp/$IP"
        run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "source /tmp/utils.sh && run_ssh_command -u $LINUX_ADMIN -h $IP -p 22 -c '/tmp/collect-logs.sh $AGENT_LOGS_DIR'" || return 1
        run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "source /tmp/utils.sh && rm -rf $AGENT_LOGS_DIR && download_files_via_scp -h $IP -p 22 -f $AGENT_LOGS_DIR $AGENT_LOGS_DIR" || return 1
        download_files_via_scp -i $PRIVATE_SSH_KEY_PATH -h $MASTER_PUBLIC_ADDRESS -p "2200" -f $AGENT_LOGS_DIR "${LOCAL_LOGS_DIR}/" || return 1
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
    upload_files_via_scp -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -f "/tmp/utils.sh" "$DIR/utils/utils.sh" || return 1
    for IP in $AGENTS_IPS; do
        AGENT_LOGS_DIR="/tmp/$IP"
        run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "source /tmp/utils.sh && mount_smb_share $IP $WIN_AGENT_ADMIN $WIN_AGENT_ADMIN_PASSWORD && mkdir -p $AGENT_LOGS_DIR && cp -rf /mnt/$IP/AzureData $AGENT_LOGS_DIR/" || return 1
        run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "if [[ -e /mnt/$IP/DCOS/environment ]]; then cp /mnt/$IP/DCOS/environment $AGENT_LOGS_DIR/; fi" || return 1
        run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "if [[ -e /mnt/$IP/Program\ Files/Docker/dockerd.log ]]; then cp /mnt/$IP/Program\ Files/Docker/dockerd.log $AGENT_LOGS_DIR/; fi" || return 1
        for SERVICE in "epmd" "mesos" "spartan" "diagnostics" "dcos-net"; do
            run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "if [[ -e /mnt/$IP/DCOS/$SERVICE/log ]] ; then mkdir -p $AGENT_LOGS_DIR/$SERVICE && cp -rf /mnt/$IP/DCOS/$SERVICE/log $AGENT_LOGS_DIR/$SERVICE/ ; fi" || return 1
            run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "if [[ -e /mnt/$IP/DCOS/$SERVICE/service/environment-file ]] ; then mkdir -p $AGENT_LOGS_DIR/$SERVICE && cp /mnt/$IP/DCOS/$SERVICE/service/environment-file $AGENT_LOGS_DIR/$SERVICE/ ; fi" || return 1
        done
        download_files_via_scp -i $PRIVATE_SSH_KEY_PATH -h $MASTER_PUBLIC_ADDRESS -p "2200" -f $AGENT_LOGS_DIR "${LOCAL_LOGS_DIR}/" || return 1
    done
}

linux_agents_private_ips() {
    if [[ ! -z $LINUX_PRIVATE_IPS ]]; then
        echo -e $LINUX_PRIVATE_IPS
        return 0
    fi
    VMSS_NAMES=$(az vmss list --resource-group $AZURE_RESOURCE_GROUP | jq -r ".[] | select(.virtualMachineProfile.osProfile.linuxConfiguration != null) | .name") || {
        echo "ERROR: Failed to get the Linux VMSS names"
        return 1
    }
    PRIVATE_IPS=""
    for VMSS_NAME in $VMSS_NAMES; do
        IPS=$(az vmss nic list --resource-group $AZURE_RESOURCE_GROUP --vmss-name $VMSS_NAME | jq -r ".[] | select(.virtualMachine != null) | .ipConfigurations[0].privateIpAddress") || {
            echo "ERROR: Failed to get VMSS $VMSS_NAME private addresses"
            return 1
        }
        PRIVATE_IPS="$IPS $PRIVATE_IPS"
    done
    export LINUX_PRIVATE_IPS="$PRIVATE_IPS"
    echo -e $LINUX_PRIVATE_IPS
}

windows_agents_private_ips() {
    if [[ ! -z $WINDOWS_PRIVATE_IPS ]]; then
        echo -e $WINDOWS_PRIVATE_IPS
        return 0
    fi
    VMSS_NAMES=$(az vmss list --resource-group $AZURE_RESOURCE_GROUP | jq -r ".[] | select(.virtualMachineProfile.osProfile.windowsConfiguration != null) | .name") || {
        echo "ERROR: Failed to get the Windows VMSS names"
        return 1
    }
    PRIVATE_IPS=""
    for VMSS_NAME in $VMSS_NAMES; do
        IPS=$(az vmss nic list --resource-group $AZURE_RESOURCE_GROUP --vmss-name $VMSS_NAME | jq -r ".[] | select(.virtualMachine != null) | .ipConfigurations[0].privateIpAddress") || {
            echo "ERROR: Failed to get VMSS $VMSS_NAME private addresses"
            return 1
        }
        PRIVATE_IPS="$IPS $PRIVATE_IPS"
    done
    export WINDOWS_PRIVATE_IPS="$PRIVATE_IPS"
    echo -e $WINDOWS_PRIVATE_IPS
}

collect_dcos_nodes_logs() {
    #
    # Collect logs from all the deployment nodes and upload them to the log server
    #
    echo "Collecting logs from all the DC/OS nodes"
    if [[ ! -z $DCOS_CLUSTER_ID ]]; then
        dcos node --json > $TEMP_LOGS_DIR/dcos-nodes.json
    fi

    # Collect logs from all the Linux master node(s)
    echo "Collecting Linux master logs"
    MASTERS_LOGS_DIR="$TEMP_LOGS_DIR/linux_masters"
    mkdir -p $MASTERS_LOGS_DIR || return 1
    collect_linux_masters_logs "$MASTERS_LOGS_DIR" || return 1

    copy_ssh_key_to_proxy_master || return 1

    IPS=$(linux_agents_private_ips)
    if [[ ! -z $IPS ]]; then
        echo "Collecting Linux agents logs"
        LINUX_LOGS_DIR="$TEMP_LOGS_DIR/linux_agents"
        mkdir -p $LINUX_LOGS_DIR || return 1
        collect_linux_agents_logs "$LINUX_LOGS_DIR" "$IPS" || return 1
    fi

    IPS=$(windows_agents_private_ips)
    if [[ ! -z $IPS ]]; then
        echo "Collecting Windows agents logs"
        WIN_LOGS_DIR="$TEMP_LOGS_DIR/windows_agents"
        mkdir -p $WIN_LOGS_DIR || return 1
        collect_windows_agents_logs "$WIN_LOGS_DIR" "$IPS" || return 1
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
    export STATUS="FAIL"
    echo "EMAIL_TITLE=[${JOB_NAME}] ${STATUS}" >> $PARAMETERS_FILE
    echo "MESSAGE=$MSG" >> $PARAMETERS_FILE
    echo "LOGS_URLS=$BUILD_OUTPUTS_URL/jenkins-console.log" >> $PARAMETERS_FILE
    job_cleanup

    # - Delete $PARAMETERS_FILE and skip e-mail notifications if the parameter EMAIL_NOTIFICATIONS is false
    if [[ "$EMAIL_NOTIFICATIONS" = "false" ]]; then
        rm -f $PARAMETERS_FILE
    fi

    echo "Ending time: $(date)"

    exit 1
}

create_testing_environment() {
    #
    # - Create the python3 virtual environment and activate it
    # - Configures the DC/OS clients for the current cluster and export the
    #   cluster ID as the DCOS_CLUSTER_ID environment variable
    #
    python3 -m venv $VENV_DIR --system-site-packages && . $VENV_DIR/bin/activate || {
        echo "ERROR: Failed to create the python3 virtualenv"
        return 1
    }
    rm -rf $DCOS_DIR || return 1
    dcos cluster setup "http://${MASTER_PUBLIC_ADDRESS}:80" || return 1
    export DCOS_CLUSTER_ID=$(dcos cluster list | egrep "http://${MASTER_PUBLIC_ADDRESS}:80" | awk '{print $2}')
    dcos cluster list | grep -q $DCOS_CLUSTER_ID || {
        echo "ERROR: Cannot find any cluster with the ID: $DCOS_CLUSTER_ID"
        return 1
    }
}

run_dcos_autoscale_job() {
    curl "${JENKINS_URL}/jnlpJars/jenkins-cli.jar" -o $JENKINS_CLI || {
        echo "ERROR: Failed to download jenkins-cli.jar from ${JENKINS_URL}"
        return 1
    }
    AUTOSCALE_JOB_NAME="dcos-testing-autoscale"
    echo "Triggering ${AUTOSCALE_JOB_NAME} job for the current DC/OS cluster"

    OUTPUT=$(java -jar $JENKINS_CLI -http -auth $JENKINS_USER:$JENKINS_PASSWORD -s $JENKINS_URL build $AUTOSCALE_JOB_NAME -s -p RESOURCE_GROUP=$AZURE_RESOURCE_GROUP)
    AUTOSCALE_EXIT_CODE=$?
    AUTOSCALE_JOB_NUMBER=$(echo $OUTPUT | grep -Eo '[0-9]+' | head -1)

    JOB_URL="${JENKINS_URL}/job/${AUTOSCALE_JOB_NAME}/${AUTOSCALE_JOB_NUMBER}"
    echo "Finished $JOB_URL"

    echo "Console output from the scale testing job:"
    curl --user ${JENKINS_USER}:${JENKINS_PASSWORD} "${JOB_URL}/consoleText" || {
        echo "Failed to download scale test console log"
        return 1
    }

    if [[ $AUTOSCALE_EXIT_CODE -ne 0 ]]; then
        echo "DC/OS autoscale testing job failed"
        return 1
    fi

    echo "DC/OS autoscale testing job succeeded"
    return 0
}

run_fluentd_tests() {
    echo "Checking if jumphost has all the required packages for winrm connection"
    setup_remote_winrm_client || return 1
    if [[ $WIN_PRIVATE_AGENT_COUNT -gt 0 ]]; then
        echo "Looking for Windows private agents"
        IPS=$($DIR/utils/dcos-node-addresses.py --operating-system 'windows' --role 'private') || return 1
        for IP in $IPS; do
            echo "Running Fluentd Pester tests on Windows private agent: $IP"
            start_fluentd_tests "$IP" || return 1
        done
    fi
    if [[ $WIN_PUBLIC_AGENT_COUNT -gt 0 ]]; then
        echo "Looking for Windows public agents"
        IPS=$($DIR/utils/dcos-node-addresses.py --operating-system 'windows' --role 'public') || return 1
        for IP in $IPS; do
            echo "Running Fluentd Pester tests on Windows public agent: $IP"
            start_fluentd_tests "$IP" || return 1
        done
    fi
}

start_fluentd_tests() {
    local AGENT_IP="$1"
    WIN_REMOTE_CLONE_DIR="C:\\mesos-jenkins"
    WIN_REMOTE_REPO_URL="https://github.com/Microsoft/mesos-jenkins"
    WIN_REMOTE_CMD="if (Test-Path -Path $WIN_REMOTE_CLONE_DIR) { Remove-Item -Force -Recurse -Path $WIN_REMOTE_CLONE_DIR }; git clone $WIN_REMOTE_REPO_URL $WIN_REMOTE_CLONE_DIR; ${WIN_REMOTE_CLONE_DIR}\\DCOS\\fluentd-testing\\run_fluentd_tests.ps1"
    JUMPHOST_REMOTE_CMD="/tmp/wsmancmd -H $AGENT_IP -s -a basic -u $WIN_AGENT_ADMIN -p $WIN_AGENT_ADMIN_PASSWORD --powershell '$WIN_REMOTE_CMD' >/tmp/winrm.stdout 2>/tmp/winrm.stderr"
    run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "$JUMPHOST_REMOTE_CMD" || {
        run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "cat /tmp/winrm.stdout ; cat /tmp/winrm.stderr"
        echo "ERROR: Fluentd tests failed on $AGENT_IP"
        return 1
    }
    run_ssh_command -i $PRIVATE_SSH_KEY_PATH -u $LINUX_ADMIN -h $MASTER_PUBLIC_ADDRESS -p "2200" -c  "cat /tmp/winrm.stdout" || return 1
    echo -e "\n"
    echo -e "Successfully ran Fluentd tests on DC/OS Windows slave ${AGENT_IP}"
    echo -e "\n"
}

successfully_exit_dcos_testing_job() {
    # - Collect all the logs in the DC/OS deployments
    collect_dcos_nodes_logs || echo "ERROR: Failed to collect DC/OS nodes logs"
    upload_logs || echo "ERROR: Failed to upload logs to log server"
    MSG="Successfully tested the Azure $DCOS_DEPLOYMENT_TYPE DC/OS deployment with "
    MSG+="the latest builds from: ${DCOS_WINDOWS_BOOTSTRAP_URL}"
    export STATUS="PASS"
    echo "EMAIL_TITLE=[${JOB_NAME}] ${STATUS}" >> $PARAMETERS_FILE
    echo "MESSAGE=$MSG" >> $PARAMETERS_FILE

    # - Do the final cleanup
    job_cleanup

    # - Delete $PARAMETERS_FILE and skip e-mail notifications if the parameter EMAIL_NOTIFICATIONS is false
    if [[ "$EMAIL_NOTIFICATIONS" = "false" ]]; then
        rm -f $PARAMETERS_FILE
    fi

    echo "Ending time: $(date)"

    echo "Successfully tested an Azure DC/OS deployment with the latest DC/OS builds"
}
