#!/bin/bash

####################################################
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
####################################################

ROOT="${DIR}/.."

# see: https://github.com/stedolan/jq/issues/105 & https://github.com/stedolan/jq/wiki/FAQ#general-questions
function jqi() { filename="${1}"; jqexpr="${2}"; jq "${jqexpr}" "${filename}" > "${filename}.tmp" && mv "${filename}.tmp" "${filename}"; }

function exit_with_msg {
	echo $1
	exit -1
}

function generate_template() {
	# Check pre-requisites
	[[ ! -z "${INSTANCE_NAME:-}" ]]      || exit_with_msg "Must specify INSTANCE_NAME"
	[[ ! -z "${CLUSTER_DEFINITION:-}" ]] || exit_with_msg "Must specify CLUSTER_DEFINITION"
	[[ ! -z "${SSH_KEY:-}" ]]            || exit_with_msg "Must specify SSH_KEY"
	[[ ! -z "${OUTPUT:-}" ]]             || exit_with_msg "Must specify OUTPUT"

	# Set output directory
	mkdir -p "${OUTPUT}"

	SSH_PUBLIC_KEY="$(cat ${SSH_KEY}.pub)"

	# Form the final cluster_definition file
	export FINAL_CLUSTER_DEFINITION="${OUTPUT}/clusterdefinition.json"
	cp "${CLUSTER_DEFINITION}" "${FINAL_CLUSTER_DEFINITION}"
	if [[ ! -z "${LINUX_VMSIZE:-}" ]]; then
		jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.masterProfile.vmSize = \"${LINUX_VMSIZE}\""
	fi
	jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.masterProfile.dnsPrefix = \"${INSTANCE_NAME}\""
	jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.linuxProfile.ssh.publicKeys[0].keyData = \"${SSH_PUBLIC_KEY}\""

	if [ "$(jq -r '.properties.windowsProfile' ${FINAL_CLUSTER_DEFINITION})" != "null" ]; then
		[[ ! -z "${WIN_PWD:-}" ]] || exit_with_msg "Must specify WIN_PWD"
		winpwd="$(cat "${WIN_PWD}")"
		jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.windowsProfile.adminPassword = \"$winpwd\""

		if [[ ! -z "${WINDOWS_IMAGE:-}" ]]; then
			if [[ $WINDOWS_IMAGE == http* ]]; then
				jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.windowsProfile.WindowsImageSourceUrl = \"$WINDOWS_IMAGE\""
			elif [[ $WINDOWS_IMAGE =~ .+,.+,.+ ]]; then
				IFS=',' read -a arr <<< "${WINDOWS_IMAGE}"
				jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.windowsProfile.WindowsPublisher = \"${arr[0]}\""
				jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.windowsProfile.WindowsOffer = \"${arr[1]}\""
				jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.windowsProfile.WindowsSku = \"${arr[2]}\""
			else
				echo "Unsupported WINDOWS_IMAGE format: $WINDOWS_IMAGE"
				exit -1
			fi
		fi
	fi

	orchestratorRelease=$(jq -r '.properties.orchestratorProfile.orchestratorRelease' ${FINAL_CLUSTER_DEFINITION})
	if [ "$orchestratorRelease" = "" ] ; then
		[[ ! -z "${ORCHESTRATOR_RELEASE:-}" ]] || exit_with_msg "Must specify ORCHESTRATOR_RELEASE"
		jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.orchestratorProfile.orchestratorRelease = \"${ORCHESTRATOR_RELEASE}\""
	fi

	# Set agents
	osTypes=$(jq -r '.properties.agentPoolProfiles[].osType' ${FINAL_CLUSTER_DEFINITION})
	oArr=( $osTypes )
	indx=0
	for os in "${oArr[@]}"; do
		dnsPrefix=$(jq -r ".properties.agentPoolProfiles[$indx].dnsPrefix" ${FINAL_CLUSTER_DEFINITION})
		if [ "$os" = "Windows" ]; then
			if [[ ! -z "${WINDOWS_VMSIZE:-}" ]]; then
				jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.agentPoolProfiles[$indx].vmSize = \"${WINDOWS_VMSIZE}\""
			fi
			if [ "$dnsPrefix" != "null" ]; then
				jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.agentPoolProfiles[$indx].dnsPrefix = \"${INSTANCE_NAME}-win\""
			fi
		else
			if [[ ! -z "${LINUX_VMSIZE:-}" ]]; then
				jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.agentPoolProfiles[$indx].vmSize = \"${LINUX_VMSIZE}\""
			fi
			if [ "$dnsPrefix" != "null" ]; then
				jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.agentPoolProfiles[$indx].dnsPrefix = \"${INSTANCE_NAME}-lnx\""
			fi
		fi
		indx=$((indx+1))
	done

	# Generate template
	"${ACS_ENGINE_EXE}" generate --output-directory "${OUTPUT}" "${FINAL_CLUSTER_DEFINITION}" --debug
}

function set_azure_account() {
	# Check pre-requisites
	[[ ! -z "${SUBSCRIPTION_ID:-}" ]] || exit_with_msg "Must specify SUBSCRIPTION_ID"
	[[ ! -z "${TENANT_ID:-}" ]]       || exit_with_msg "Must specify TENANT_ID"
	[[ ! -z "${SERVICE_PRINCIPAL_CLIENT_ID:-}" ]]     || exit_with_msg "Must specify SERVICE_PRINCIPAL_CLIENT_ID"
	[[ ! -z "${SERVICE_PRINCIPAL_CLIENT_SECRET:-}" ]] || exit_with_msg "Must specify SERVICE_PRINCIPAL_CLIENT_SECRET"

	which az || exit_with_msg "az must be on PATH"

	# Login to Azure-Cli
	az login --service-principal \
		--username "${SERVICE_PRINCIPAL_CLIENT_ID}" \
		--password "${SERVICE_PRINCIPAL_CLIENT_SECRET}" \
		--tenant "${TENANT_ID}" &>/dev/null

	az account set --subscription "${SUBSCRIPTION_ID}"
}

function get_secrets() {
	[[ ! -z "${DATA_DIR:-}" ]] || exit_with_msg "Must specify DATA_DIR"

	if [[ ! -z "${KEYVAULT_NAME:-}" ]]; then
		if [[ ! -z "${SSH_KEY_SECRET_NAME:-}" ]]; then
			echo "Retrieving SSH key pair from keyvault"
			az keyvault secret download --vault-name ${KEYVAULT_NAME} --name ${SSH_KEY_SECRET_NAME} --file ${DATA_DIR}/id_rsa.b64 && \
				base64 -d ${DATA_DIR}/id_rsa.b64 > ${DATA_DIR}/id_rsa && \
				chmod 600 ${DATA_DIR}/id_rsa

			az keyvault secret download --vault-name ${KEYVAULT_NAME} --name "${SSH_KEY_SECRET_NAME}-pub" --file ${DATA_DIR}/id_rsa.pub && \
				chmod 600 ${DATA_DIR}/id_rsa.pub
		fi
		if [[ ! -z "${WINDOWS_PASSWORD_SECRET_NAME:-}" ]]; then
			echo "Retrieving Windows password from keyvault"
			az keyvault secret download --vault-name ${KEYVAULT_NAME} --name ${WINDOWS_PASSWORD_SECRET_NAME} --file ${DATA_DIR}/win.pwd
		fi
	fi

	if [ ! -e "${DATA_DIR}/id_rsa" ]; then
		echo "Generate SSH key pair"
		ssh-keygen -b 2048 -t rsa -f "${DATA_DIR}/id_rsa" -q -N ""
		ssh-keygen -y -f "${DATA_DIR}/id_rsa" > "${DATA_DIR}/id_rsa.pub"
	fi

	if [ ! -e "${DATA_DIR}/win.pwd" ]; then
		echo "Generate Windows Password"
		winpwd="Wp@1$(date +%s | sha256sum | base64 | head -c 32)"
		echo "$winpwd" > ${DATA_DIR}/win.pwd
	fi
}

function create_resource_group() {
	[[ ! -z "${LOCATION:-}" ]]       || exit_with_msg "Must specify LOCATION"
	[[ ! -z "${RESOURCE_GROUP:-}" ]] || exit_with_msg "Must specify RESOURCE_GROUP"

	# Create resource group if doesn't exist
	rg=$(az group show --name="${RESOURCE_GROUP}")
	if [ -z "$rg" ]; then
		az group create --name="${RESOURCE_GROUP}" --location="${LOCATION}" --tags "type=${RESOURCE_GROUP_TAG_TYPE:-}" "now=$(date +%s)" "job=${JOB_BASE_NAME:-}" "buildno=${BUILD_NUMBER:-}"
		sleep 3 # TODO: investigate why this is needed (eventual consistency in ARM)
	fi
}

function deploy_template() {
	# Check pre-requisites
	[[ ! -z "${DEPLOYMENT_NAME:-}" ]] || exit_with_msg "Must specify DEPLOYMENT_NAME"
	[[ ! -z "${LOCATION:-}" ]]        || exit_with_msg "Must specify LOCATION"
	[[ ! -z "${RESOURCE_GROUP:-}" ]]  || exit_with_msg "Must specify RESOURCE_GROUP"
	[[ ! -z "${OUTPUT:-}" ]]          || exit_with_msg "Must specify OUTPUT"

	which az || exit_with_msg "az must be on PATH"

	create_resource_group

	# Deploy the template
	az group deployment create \
		--name "${DEPLOYMENT_NAME}" \
		--resource-group "${RESOURCE_GROUP}" \
		--template-file "${OUTPUT}/azuredeploy.json" \
		--parameters "@${OUTPUT}/azuredeploy.parameters.json"
}

function scale_agent_pool() {
	# Check pre-requisites
	[[ ! -z "${AGENT_POOL_SIZE:-}" ]] || exit_with_msg "Must specify AGENT_POOL_SIZE"
	[[ ! -z "${DEPLOYMENT_NAME:-}" ]] || exit_with_msg "Must specify DEPLOYMENT_NAME"
	[[ ! -z "${LOCATION:-}" ]]        || exit_with_msg "Must specify LOCATION"
	[[ ! -z "${RESOURCE_GROUP:-}" ]]  || exit_with_msg "Must specify RESOURCE_GROUP"
	[[ ! -z "${OUTPUT:-}" ]]          || exit_with_msg "Must specify OUTPUT"

	which az || exit_with_msg "az must be on PATH"

	APIMODEL="${OUTPUT}/apimodel.json"
	DEPLOYMENT_PARAMS="${OUTPUT}/azuredeploy.parameters.json"

	for poolname in `jq '.properties.agentPoolProfiles[].name' "${APIMODEL}" | tr -d '\"'`; do
	  offset=$(jq "getpath([\"parameters\", \"${poolname}Count\", \"value\"])" ${DEPLOYMENT_PARAMS})
	  echo "$poolname : offset=$offset count=$AGENT_POOL_SIZE"
	  jqi "${DEPLOYMENT_PARAMS}" ".${poolname}Count.value = $AGENT_POOL_SIZE"
	  jqi "${DEPLOYMENT_PARAMS}" ".${poolname}Offset.value = $offset"
	done

	az group deployment create \
		--name "${DEPLOYMENT_NAME}" \
		--resource-group "${RESOURCE_GROUP}" \
		--template-file "${OUTPUT}/azuredeploy.json" \
		--parameters "@${OUTPUT}/azuredeploy.parameters.json"
}

function get_node_count() {
	[[ ! -z "${CLUSTER_DEFINITION:-}" ]] || exit_with_msg "Must specify CLUSTER_DEFINITION"

	masters=$(jq '.properties.masterProfile.count' ${CLUSTER_DEFINITION})
	linux_agents=0
	windows_agents=0
	count=$masters

	nodes=$(jq -r '.properties.agentPoolProfiles[].count' ${CLUSTER_DEFINITION})
	osTypes=$(jq -r '.properties.agentPoolProfiles[].osType' ${CLUSTER_DEFINITION})

	nArr=( $nodes )
	oArr=( $osTypes )
	indx=0
	for n in "${nArr[@]}"; do
		count=$((count+n))
		if [ "${oArr[$indx]}" = "Windows" ]; then
			windows_agents=$((windows_agents+n))
		else
			linux_agents=$((linux_agents+n))
		fi
		indx=$((indx+1))
	done
	echo "${count}:$masters:${linux_agents}:${windows_agents}"
}

function get_orchestrator_type() {
	[[ ! -z "${CLUSTER_DEFINITION:-}" ]] || exit_with_msg "Must specify CLUSTER_DEFINITION"

	orchestratorType=$(jq -r 'getpath(["properties","orchestratorProfile","orchestratorType"])' ${CLUSTER_DEFINITION} | tr '[:upper:]' '[:lower:]')

	echo $orchestratorType
}

function get_orchestrator_version() {
	[[ ! -z "${OUTPUT:-}" ]] || exit_with_msg "Must specify OUTPUT"

	orchestratorVersion=$(jq -r 'getpath(["properties","orchestratorProfile","orchestratorVersion"])' ${OUTPUT}/apimodel.json)
	if [[ "$orchestratorVersion" == "null" ]]; then
		orchestratorVersion=""
	fi

	echo $orchestratorVersion
}

function get_api_version() {
	[[ ! -z "${CLUSTER_DEFINITION:-}" ]] || exit_with_msg "Must specify CLUSTER_DEFINITION"

	apiVersion=$(jq -r 'getpath(["apiVersion"])' ${CLUSTER_DEFINITION})
	if [[ "$apiVersion" == "null" ]]; then
		apiVersion=""
	fi

	echo $apiVersion
}

function validate_agents {
	OS=$1
	MARATHON_JSON=$2
	[[ ! -z "${MARATHON_JSON:-}" ]] || exit_with_msg "Marathon JSON filename is not passed"
	[[ ! -z "${INSTANCE_NAME:-}" ]] || exit_with_msg "Must specify INSTANCE_NAME"
	[[ ! -z "${LOCATION:-}" ]]      || exit_with_msg "Must specify LOCATION"
	[[ ! -z "${SSH_KEY:-}" ]]       || exit_with_msg "Must specify SSH_KEY"

	local remote_exec="ssh -i "${SSH_KEY}" -o ConnectTimeout=30 -o StrictHostKeyChecking=no azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com -p2200"
	local remote_cp="scp -i "${SSH_KEY}" -P 2200 -o StrictHostKeyChecking=no"

	local appID="/$(jq -r .id ${ROOT}/${MARATHON_JSON})"
	local instances="$(jq -r .instances ${ROOT}/${MARATHON_JSON})"

	echo $(date +%H:%M:%S) "Copying ${MARATHON_JSON} id:$appID instances:$instances"

	${remote_cp} "${ROOT}/${MARATHON_JSON}" azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com:${MARATHON_JSON}
	[ $? -eq 0 ] || exit_with_msg "Error: failed to copy ${MARATHON_JSON}"

	if [[ "$OS" == "Linux" ]]; then
		local agentFQDN="${INSTANCE_NAME}-lnx.${LOCATION}.cloudapp.azure.com"
	else
		local agentFQDN="${INSTANCE_NAME}-win.${LOCATION}.cloudapp.azure.com"
	fi

	${remote_exec} sed -i "s/{agentFQDN}/${agentFQDN}/g" ${MARATHON_JSON}
	[ $? -eq 0 ] || exit_with_msg "Error: failed to configure ${MARATHON_JSON}"

	echo $(date +%H:%M:%S) "Adding marathon app"
	count=20
	while (( $count > 0 )); do
		echo $(date +%H:%M:%S) "  ... counting down $count"
		${remote_exec} ./dcos marathon app list | grep $appID
		retval=$?
		[ $retval -eq 0 ] && echo "Marathon App successfully installed" && break
		${remote_exec} ./dcos marathon app add ${MARATHON_JSON}
		retval=$?
		[ $retval -eq 0 ] && break
		sleep 15; count=$((count-1))
	done
	[ $retval -eq 0 ] || exit_with_msg "Error: gave up waiting for marathon to be added"

	# only need to teardown if app added successfully
	trap "${remote_exec} ./dcos marathon app remove $appID" EXIT

	echo $(date +%H:%M:%S) "Validating marathon app"
	count=50
	while (( ${count} > 0 )); do
		echo $(date +%H:%M:%S) "  ... counting down $count"
		appStatus=$(${remote_exec} ./dcos marathon app show $appID)
		running=$(echo $appStatus | jq .tasksRunning)
		healthy=$(echo $appStatus | jq .tasksHealthy)
		if [ "$running" = "$instances" ] && [ "$healthy" = "$instances" ]; then
			echo $(date +%H:%M:%S) "Found $instances running/healthy tasks"
			break
		fi
		sleep 30
		count=$((count-1))
	done

	if [ "$running" != "$instances" ] || [ "$healthy" != "$instances" ]; then
		echo "Error: marathon validation: tasksRunning $running, tasksHealthy $healthy, expected $instances"
		${remote_exec} ./dcos marathon app show $appID
		${remote_exec} ./dcos marathon app list
		exit 1
	fi

	# curl webserver through external haproxy
	echo $(date +%H:%M:%S) "Checking Service"
	count=20
	while true; do
		echo $(date +%H:%M:%S) "  ... counting down $count"
		rc=$(curl -sI --max-time 60 "http://${agentFQDN}" | head -n1 | cut -d$' ' -f2)
		[[ "$rc" -eq "200" ]] && echo "Successfully hitting simpleweb through external haproxy http://${agentFQDN}" && break
		[ ${count} -gt 0 ] || exit_with_msg "Error: failed to get expected response from nginx through the loadbalancer ($rc)"
		sleep 15
		count=$((count-1))
	done
}

function validate_master_agent_authentication() {
	echo $(date +%H:%M:%S) "Validating master-agent authentication"

	[[ ! -z "${INSTANCE_NAME:-}" ]]         || exit_with_msg "Must specify INSTANCE_NAME"
	[[ ! -z "${LOCATION:-}" ]]              || exit_with_msg "Must specify LOCATION"
	[[ ! -z "${EXPECTED_MASTER_COUNT:-}" ]] || exit_with_msg "Must specify EXPECTED_MASTER_COUNT"
	[[ ! -z "${SSH_KEY:-}" ]]               || exit_with_msg "Must specify SSH_KEY"

	for i in `seq 0 $(($EXPECTED_MASTER_COUNT - 1))`; do
		local port=$((i+2200))
		local remote_exec="ssh -i "${SSH_KEY}" -o ConnectTimeout=30 -o StrictHostKeyChecking=no azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com -p $port"

		auth_enabled=$(${remote_exec} 'curl -s http://$(/opt/mesosphere/bin/detect_ip):5050/flags' | jq -r ".flags.authenticate_agents") || {
			exit_with_msg "Error: failed to find the Mesos flags on the master $i"
		}
		[[ "$auth_enabled" = "true" ]] || exit_with_msg "Error: master $i doesn't have 'authenticate_agents' flag enabled"
	done
	echo $(date +%H:%M:%S) "All masters have the authenticate_agents flag enabled"
}

function validate() {
	[[ ! -z "${INSTANCE_NAME:-}" ]]           || exit_with_msg "Must specify INSTANCE_NAME"
	[[ ! -z "${LOCATION:-}" ]]                || exit_with_msg "Must specify LOCATION"
	[[ ! -z "${SSH_KEY:-}" ]]                 || exit_with_msg "Must specify SSH_KEY"
	[[ ! -z "${EXPECTED_NODE_COUNT:-}" ]]     || exit_with_msg "Must specify EXPECTED_NODE_COUNT"
	[[ ! -z "${EXPECTED_LINUX_AGENTS:-}" ]]   || exit_with_msg "Must specify EXPECTED_LINUX_AGENTS"
	[[ ! -z "${EXPECTED_WINDOWS_AGENTS:-}" ]] || exit_with_msg "Must specify EXPECTED_WINDOWS_AGENTS"
	[[ ! -z "${OUTPUT:-}" ]]                  || exit_with_msg "Must specify OUTPUT"

	local remote_exec="ssh -i "${SSH_KEY}" -o ConnectTimeout=30 -o StrictHostKeyChecking=no azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com -p2200"

	echo $(date +%H:%M:%S) "Checking node count"
	count=20
	while (( $count > 0 )); do
		echo $(date +%H:%M:%S) "  ... counting down $count"
		local node_count=$(${remote_exec} curl -s http://localhost:1050/system/health/v1/nodes | jq '.nodes | length')
		[ $? -eq 0 ] && [ ! -z "$node_count" ] && [ $node_count -eq ${EXPECTED_NODE_COUNT} ] && echo "Successfully got $EXPECTED_NODE_COUNT nodes" && break
		sleep 30
		count=$((count-1))
	done
	if (( $node_count != ${EXPECTED_NODE_COUNT} )); then
		echo "Error: gave up waiting for DCOS nodes: $node_count available, ${EXPECTED_NODE_COUNT} expected"
		exit 1
	fi

	echo $(date +%H:%M:%S) "Checking node health"
	count=20
	while (( $count > 0 )); do
		echo $(date +%H:%M:%S) "  ... counting down $count"
		local unhealthy_nodes=$(${remote_exec} curl -s http://localhost:1050/system/health/v1/nodes | jq '.nodes[] | select(.health != 0)')
		[ $? -eq 0 ] && [ -z "$unhealthy_nodes" ] && echo "All nodes are healthy" && break
		sleep 30; count=$((count-1))
	done
	[[ -z "$unhealthy_nodes" ]] || exit_with_msg "Error: unhealthy nodes: $unhealthy_nodes"

	if [[ "${MASTER_AGENT_AUTHENTICATION:-}" == "true" ]]; then
		validate_master_agent_authentication
	fi

	echo $(date +%H:%M:%S) "Downloading dcos"
	${remote_exec} curl -O https://downloads.dcos.io/binaries/cli/linux/x86-64/dcos-1.10/dcos
	[ $? -eq 0 ] || exit_with_msg "Error: failed to download dcos"
	echo $(date +%H:%M:%S) "Setting dcos permissions"
	${remote_exec} chmod a+x ./dcos
	[ $? -eq 0 ] || exit_with_msg "Error: failed to chmod dcos"
	echo $(date +%H:%M:%S) "Configuring dcos"
	${remote_exec} ./dcos cluster setup http://localhost:80
	[ $? -eq 0 ] || exit_with_msg "Error: failed to configure dcos"

	echo $(date +%H:%M:%S) "Installing marathon-lb"
	${remote_exec} ./dcos package install marathon-lb --yes
	[ $? -eq 0 ] || exit_with_msg "Error: failed to install marathon-lb"

	if (( ${EXPECTED_LINUX_AGENTS} > 0 )); then
		validate_agents "Linux" "nginx-marathon-template.json"
	fi

	if (( ${EXPECTED_WINDOWS_AGENTS} > 0 )); then
		if [[ ! -z "${WINDOWS_MARATHON_APP:-}" ]]; then
			validate_agents "Windows" "${WINDOWS_MARATHON_APP}"
		fi
	fi
}

function cleanup() {
	echo $(date +%H:%M:%S) "cleanup: CLEANUP=${CLEANUP:-}"
	if [ "${CLEANUP:-}" = true ]; then
		echo "Deleting ${RESOURCE_GROUP}"
		az group delete --no-wait --name="${RESOURCE_GROUP}" --yes || true
	fi
}
