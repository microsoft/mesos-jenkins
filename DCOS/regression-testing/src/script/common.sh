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

function generate_template() {
	# Check pre-requisites
	[[ ! -z "${INSTANCE_NAME:-}" ]]      || (echo "Must specify INSTANCE_NAME" && exit -1)
	[[ ! -z "${CLUSTER_DEFINITION:-}" ]] || (echo "Must specify CLUSTER_DEFINITION" && exit -1)
	[[ ! -z "${OUTPUT:-}" ]]             || (echo "Must specify OUTPUT" && exit -1)

	# Set output directory
	mkdir -p "${OUTPUT}"

	# Prep SSH Key
	if [[ -z "${SSH_KEY_DATA:-}" ]]; then
		ssh-keygen -b 2048 -t rsa -f "${OUTPUT}/id_rsa" -q -N ""
		ssh-keygen -y -f "${OUTPUT}/id_rsa" > "${OUTPUT}/id_rsa.pub"
		export SSH_KEY_DATA="$(cat "${OUTPUT}/id_rsa.pub")"
		export SSH_KEY="${OUTPUT}/id_rsa"
	fi

	# Form the final cluster_definition file
	export FINAL_CLUSTER_DEFINITION="${OUTPUT}/clusterdefinition.json"
	cp "${CLUSTER_DEFINITION}" "${FINAL_CLUSTER_DEFINITION}"
	jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.masterProfile.dnsPrefix = \"${INSTANCE_NAME}\""
	jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.linuxProfile.ssh.publicKeys[0].keyData = \"${SSH_KEY_DATA}\""
	if [ "$(jq -r '.properties.windowsProfile' ${FINAL_CLUSTER_DEFINITION})" != "null" ]; then
		winpwd=$(date +%s | sha256sum | base64 | head -c 32)
		jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.windowsProfile.adminPassword = \"$winpwd\""
	fi

	orchestratorRelease=$(jq -r '.properties.orchestratorProfile.orchestratorRelease' ${FINAL_CLUSTER_DEFINITION})
	if [ "$orchestratorRelease" = "" ] ; then
		[[ ! -z "${ORCHESTRATOR_RELEASE:-}" ]] || (echo "Must specify ORCHESTRATOR_RELEASE" && exit -1)
		jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.orchestratorProfile.orchestratorRelease = \"${ORCHESTRATOR_RELEASE}\""
	fi

	# Set dnsPrefix
	osTypes=$(jq -r '.properties.agentPoolProfiles[].osType' ${FINAL_CLUSTER_DEFINITION})
	oArr=( $osTypes )
	indx=0
	for n in "${oArr[@]}"; do
		dnsPrefix=$(jq -r ".properties.agentPoolProfiles[$indx].dnsPrefix" ${FINAL_CLUSTER_DEFINITION})
		if [ "$dnsPrefix" != "null" ]; then
			if [ "${oArr[$indx]}" = "Windows" ]; then
				jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.agentPoolProfiles[$indx].dnsPrefix = \"${INSTANCE_NAME}-w$indx\""
			else
				jqi "${FINAL_CLUSTER_DEFINITION}" ".properties.agentPoolProfiles[$indx].dnsPrefix = \"${INSTANCE_NAME}-l$indx\""
			fi
		fi
		indx=$((indx+1))
	done

	# Generate template
	"${ACS_ENGINE_EXE}" generate --output-directory "${OUTPUT}" "${FINAL_CLUSTER_DEFINITION}" --debug
}

function set_azure_account() {
	# Check pre-requisites
	[[ ! -z "${SUBSCRIPTION_ID:-}" ]] || (echo "Must specify SUBSCRIPTION_ID" && exit -1)
	[[ ! -z "${TENANT_ID:-}" ]] || (echo "Must specify TENANT_ID" && exit -1)
	[[ ! -z "${SERVICE_PRINCIPAL_CLIENT_ID:-}" ]] || (echo "Must specify SERVICE_PRINCIPAL_CLIENT_ID" && exit -1)
	[[ ! -z "${SERVICE_PRINCIPAL_CLIENT_SECRET:-}" ]] || (echo "Must specify SERVICE_PRINCIPAL_CLIENT_SECRET" && exit -1)
	which az || (echo "az must be on PATH" && exit -1)

	# Login to Azure-Cli
	az login --service-principal \
		--username "${SERVICE_PRINCIPAL_CLIENT_ID}" \
		--password "${SERVICE_PRINCIPAL_CLIENT_SECRET}" \
		--tenant "${TENANT_ID}" &>/dev/null

	az account set --subscription "${SUBSCRIPTION_ID}"
}

function create_resource_group() {
	[[ ! -z "${LOCATION:-}" ]] || (echo "Must specify LOCATION" && exit -1)
	[[ ! -z "${RESOURCE_GROUP:-}" ]] || (echo "Must specify RESOURCE_GROUP" && exit -1)

	# Create resource group if doesn't exist
	rg=$(az group show --name="${RESOURCE_GROUP}")
	if [ -z "$rg" ]; then
		az group create --name="${RESOURCE_GROUP}" --location="${LOCATION}" --tags "type=${RESOURCE_GROUP_TAG_TYPE:-}" "now=$(date +%s)" "job=${JOB_BASE_NAME:-}" "buildno=${BUILD_NUMBER:-}"
		sleep 3 # TODO: investigate why this is needed (eventual consistency in ARM)
	fi
}

function deploy_template() {
	# Check pre-requisites
	[[ ! -z "${DEPLOYMENT_NAME:-}" ]] || (echo "Must specify DEPLOYMENT_NAME" && exit -1)
	[[ ! -z "${LOCATION:-}" ]] || (echo "Must specify LOCATION" && exit -1)
	[[ ! -z "${RESOURCE_GROUP:-}" ]] || (echo "Must specify RESOURCE_GROUP" && exit -1)
	[[ ! -z "${OUTPUT:-}" ]] || (echo "Must specify OUTPUT" && exit -1)

	which az || (echo "az must be on PATH" && exit -1)

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
	[[ ! -z "${AGENT_POOL_SIZE:-}" ]] || (echo "Must specify AGENT_POOL_SIZE" && exit -1)
	[[ ! -z "${DEPLOYMENT_NAME:-}" ]] || (echo "Must specify DEPLOYMENT_NAME" && exit -1)
	[[ ! -z "${LOCATION:-}" ]] || (echo "Must specify LOCATION" && exit -1)
	[[ ! -z "${RESOURCE_GROUP:-}" ]] || (echo "Must specify RESOURCE_GROUP" && exit -1)
	[[ ! -z "${OUTPUT:-}" ]] || (echo "Must specify OUTPUT" && exit -1)

	which az || (echo "az must be on PATH" && exit -1)

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
	[[ ! -z "${CLUSTER_DEFINITION:-}" ]] || (echo "Must specify CLUSTER_DEFINITION" && exit -1)

	count=$(jq '.properties.masterProfile.count' ${CLUSTER_DEFINITION})
	linux_agents=0
	windows_agents=0

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
	echo "${count}:${linux_agents}:${windows_agents}"
}

function get_orchestrator_type() {
	[[ ! -z "${CLUSTER_DEFINITION:-}" ]] || (echo "Must specify CLUSTER_DEFINITION" && exit -1)

	orchestratorType=$(jq -r 'getpath(["properties","orchestratorProfile","orchestratorType"])' ${CLUSTER_DEFINITION} | tr '[:upper:]' '[:lower:]')

	echo $orchestratorType
}

function get_orchestrator_version() {
	[[ ! -z "${OUTPUT:-}" ]] || (echo "Must specify OUTPUT" && exit -1)

	orchestratorVersion=$(jq -r 'getpath(["properties","orchestratorProfile","orchestratorVersion"])' ${OUTPUT}/apimodel.json)
	if [[ "$orchestratorVersion" == "null" ]]; then
		orchestratorVersion=""
	fi

	echo $orchestratorVersion
}

function get_api_version() {
	[[ ! -z "${CLUSTER_DEFINITION:-}" ]] || (echo "Must specify CLUSTER_DEFINITION" && exit -1)

	apiVersion=$(jq -r 'getpath(["apiVersion"])' ${CLUSTER_DEFINITION})
	if [[ "$apiVersion" == "null" ]]; then
		apiVersion=""
	fi

	echo $apiVersion
}

function validate_agents {
	MARATHON_JSON=$1
	[[ ! -z "${MARATHON_JSON:-}" ]] || (echo "Marathon JSON filename is not passed" && exit -1)
	[[ ! -z "${INSTANCE_NAME:-}" ]] || (echo "Must specify INSTANCE_NAME" && exit -1)
	[[ ! -z "${LOCATION:-}" ]]      || (echo "Must specify LOCATION" && exit -1)
	[[ ! -z "${SSH_KEY:-}" ]]       || (echo "Must specify SSH_KEY" && exit -1)

	remote_exec="ssh -i "${SSH_KEY}" -o ConnectTimeout=30 -o StrictHostKeyChecking=no azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com -p2200"
	remote_cp="scp -i "${SSH_KEY}" -P 2200 -o StrictHostKeyChecking=no"

	appID="/$(jq -r .id ${MARATHON_JSON})"
	instances="$(jq -r .instances ${MARATHON_JSON})"

	echo $(date +%H:%M:%S) "Copying ${MARATHON_JSON} id:$appID instances:$instances"

	${remote_cp} "${ROOT}/${MARATHON_JSON}" azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com:${MARATHON_JSON}
	if [[ "$?" != "0" ]]; then echo "Error: failed to copy ${MARATHON_JSON}"; exit 1; fi

	echo $(date +%H:%M:%S) "Adding marathon app"
	count=20
	while (( $count > 0 )); do
		echo $(date +%H:%M:%S) "  ... counting down $count"
		${remote_exec} ./dcos marathon app list | grep $appID
		retval=$?
		if [[ $retval -eq 0 ]]; then echo "Marathon App successfully installed" && break; fi
		${remote_exec} ./dcos marathon app add ${MARATHON_JSON}
		retval=$?
		if [[ "$retval" == "0" ]]; then break; fi
			sleep 15; count=$((count-1))
	done
	if [[ $retval -ne 0 ]]; then echo "Error: gave up waiting for marathon to be added"; exit 1; fi

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
		sleep 30; count=$((count-1))
	done

	if [ "$running" != "$instances" ] || [ "$healthy" != "$instances" ]; then
		echo "Error: marathon validation: tasksRunning $running, tasksHealthy $healthy, expected $instances"
		${remote_exec} ./dcos marathon app show $appID
		${remote_exec} ./dcos marathon app list
		exit 1
	fi
}

function validate() {
	[[ ! -z "${INSTANCE_NAME:-}" ]]           || (echo "Must specify INSTANCE_NAME" && exit -1)
	[[ ! -z "${LOCATION:-}" ]]                || (echo "Must specify LOCATION" && exit -1)
	[[ ! -z "${SSH_KEY:-}" ]]                 || (echo "Must specify SSH_KEY" && exit -1)
	[[ ! -z "${EXPECTED_NODE_COUNT:-}" ]]     || (echo "Must specify EXPECTED_NODE_COUNT" && exit -1)
	[[ ! -z "${EXPECTED_LINUX_AGENTS:-}" ]]   || (echo "Must specify EXPECTED_LINUX_AGENTS" && exit -1)
	[[ ! -z "${EXPECTED_WINDOWS_AGENTS:-}" ]] || (echo "Must specify EXPECTED_WINDOWS_AGENTS" && exit -1)
	[[ ! -z "${OUTPUT:-}" ]]                  || (echo "Must specify OUTPUT" && exit -1)

	remote_exec="ssh -i "${SSH_KEY}" -o ConnectTimeout=30 -o StrictHostKeyChecking=no azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com -p2200"

	echo $(date +%H:%M:%S) "Checking node count"
	count=20
	while (( $count > 0 )); do
		echo $(date +%H:%M:%S) "  ... counting down $count"
		node_count=$(${remote_exec} curl -s http://localhost:1050/system/health/v1/nodes | jq '.nodes | length')
		[ $? -eq 0 ] && [ ! -z "$node_count" ] && [ $node_count -eq ${EXPECTED_NODE_COUNT} ] && echo "Successfully got $EXPECTED_NODE_COUNT nodes" && break
		sleep 30; count=$((count-1))
	done
	if (( $node_count != ${EXPECTED_NODE_COUNT} )); then
		echo "Error: gave up waiting for DCOS nodes: $node_count available, ${EXPECTED_NODE_COUNT} expected"
		exit 1
	fi

	echo $(date +%H:%M:%S) "Checking node health"
	count=20
	while (( $count > 0 )); do
		echo $(date +%H:%M:%S) "  ... counting down $count"
		unhealthy_nodes=$(${remote_exec} curl -s http://localhost:1050/system/health/v1/nodes | jq '.nodes[] | select(.health != 0)')
		[ $? -eq 0 ] && [ -z "$unhealthy_nodes" ] && echo "All nodes are healthy" && break
		sleep 30; count=$((count-1))
	done
	if [[ ! -z "$unhealthy_nodes" ]]; then echo "Error: unhealthy nodes: $unhealthy_nodes"; exit 1; fi

	echo $(date +%H:%M:%S) "Downloading dcos"
	${remote_exec} curl -O https://downloads.dcos.io/binaries/cli/linux/x86-64/dcos-1.10/dcos
	if [[ "$?" != "0" ]]; then echo "Error: failed to download dcos"; exit 1; fi
	echo $(date +%H:%M:%S) "Setting dcos permissions"
	${remote_exec} chmod a+x ./dcos
	if [[ "$?" != "0" ]]; then echo "Error: failed to chmod dcos"; exit 1; fi
	echo $(date +%H:%M:%S) "Configuring dcos"
	${remote_exec} ./dcos cluster setup http://localhost:80
	if [[ "$?" != "0" ]]; then echo "Error: failed to configure dcos"; exit 1; fi

	if (( ${EXPECTED_LINUX_AGENTS} > 0 )); then
		validate_agents "nginx-marathon-template.json"
	fi

	if (( ${EXPECTED_WINDOWS_AGENTS} > 0 )); then
		validate_agents "iis-marathon-template.json"
	fi
}

function cleanup() {
	echo $(date +%H:%M:%S) "cleanup: CLEANUP=${CLEANUP:-}"
	if [ "${CLEANUP:-}" = true ]; then
		echo "Deleting ${RESOURCE_GROUP}"
		az group delete --no-wait --name="${RESOURCE_GROUP}" --yes || true
	fi
}
