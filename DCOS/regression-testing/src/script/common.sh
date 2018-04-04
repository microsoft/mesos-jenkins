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
		if [ $dnsPrefix != "null" ]; then
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

function validate_linux_agent {
	[[ ! -z "${INSTANCE_NAME:-}" ]] || (echo "Must specify INSTANCE_NAME" && exit -1)
	[[ ! -z "${LOCATION:-}" ]]      || (echo "Must specify LOCATION" && exit -1)
	[[ ! -z "${SSH_KEY:-}" ]]       || (echo "Must specify SSH_KEY" && exit -1)

	agentFQDN=$1

	remote_exec="ssh -i "${SSH_KEY}" -o ConnectTimeout=30 -o StrictHostKeyChecking=no azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com -p2200"
	remote_cp="scp -i "${SSH_KEY}" -P 2200 -o StrictHostKeyChecking=no"

	echo "Copying marathon.json"

	${remote_cp} "${DIR}/marathon-slave-public.json" azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com:marathon.json
	if [[ "$?" != "0" ]]; then echo "Failed to copy marathon.json"; exit 1; fi

	# feed agentFQDN to marathon.json
	echo "Configuring marathon.json"
	${remote_exec} sed -i "s/{agentFQDN}/${agentFQDN}/g" marathon.json
	if [[ "$?" != "0" ]]; then echo "Failed to configure marathon.json"; exit 1; fi

	echo "Adding marathon app"
	count=20
	while (( $count > 0 )); do
		echo "  ... counting down $count"
		${remote_exec} ./dcos marathon app list | grep /web
		retval=$?
		if [[ $retval -eq 0 ]]; then echo "Marathon App successfully installed" && break; fi
		${remote_exec} ./dcos marathon app add marathon.json
		retval=$?
		if [[ "$retval" == "0" ]]; then break; fi
			sleep 15; count=$((count-1))
	done
	if [[ $retval -ne 0 ]]; then echo "gave up waiting for marathon to be added"; exit 1; fi

	# only need to teardown if app added successfully
	trap "${remote_exec} ./dcos marathon app remove /web || true" EXIT

	echo "Validating marathon app"
	count=0
	while [[ ${count} -lt 25 ]]; do
		count=$((count+1))
		echo "  ... cycle $count"
		running=$(${remote_exec} ./dcos marathon app show /web | jq .tasksRunning)
		if [[ "${running}" == "3" ]]; then
			echo "Found 3 running tasks"
			break
		fi
		sleep ${count}
	done

	if [[ "${running}" != "3" ]]; then
		echo "marathon validation failed"
		${remote_exec} ./dcos marathon app show /web
		${remote_exec} ./dcos marathon app list
		exit 1
	fi

	# install marathon-lb
	${remote_exec} ./dcos package install marathon-lb --yes
	if [[ "$?" != "0" ]]; then echo "Failed to install marathon-lb"; exit 1; fi

	# curl simpleweb through external haproxy
	echo "Checking Service"
	count=20
	while true; do
		echo "  ... counting down $count"
		rc=$(curl -sI --max-time 60 "http://${agentFQDN}" | head -n1 | cut -d$' ' -f2)
		[[ "$rc" -eq "200" ]] && echo "Successfully hitting simpleweb through external haproxy http://${agentFQDN}" && break
		if [[ "${count}" -le 1 ]]; then
			echo "failed to get expected response from nginx through the loadbalancer: Error $rc"
			exit 1
		fi
		sleep 15; count=$((count-1))
	done

	${remote_exec} ./dcos marathon app remove /web || true
}

function validate() {
	set -x
	[[ ! -z "${INSTANCE_NAME:-}" ]]       || (echo "Must specify INSTANCE_NAME" && exit -1)
	[[ ! -z "${LOCATION:-}" ]]            || (echo "Must specify LOCATION" && exit -1)
	[[ ! -z "${SSH_KEY:-}" ]]             || (echo "Must specify SSH_KEY" && exit -1)
	[[ ! -z "${EXPECTED_NODE_COUNT:-}" ]] || (echo "Must specify EXPECTED_NODE_COUNT" && exit -1)
	[[ ! -z "${OUTPUT:-}" ]]              || (echo "Must specify OUTPUT" && exit -1)

	remote_exec="ssh -i "${SSH_KEY}" -o ConnectTimeout=30 -o StrictHostKeyChecking=no azureuser@${INSTANCE_NAME}.${LOCATION}.cloudapp.azure.com -p2200"

	echo "Checking node count"
	count=20
	while (( $count > 0 )); do
		echo "  ... counting down $count"
		node_count=$(${remote_exec} curl -s http://localhost:1050/system/health/v1/nodes | jq '.nodes | length')
		[ $? -eq 0 ] && [ ! -z "$node_count" ] && [ $node_count -eq ${EXPECTED_NODE_COUNT} ] && echo "Successfully got $EXPECTED_NODE_COUNT nodes" && break
		sleep 30; count=$((count-1))
	done
	if (( $node_count != ${EXPECTED_NODE_COUNT} )); then
		echo "gave up waiting for DCOS nodes: $node_count available, ${EXPECTED_NODE_COUNT} expected"
		exit 1
	fi

	echo "Downloading dcos"
	${remote_exec} curl -O https://downloads.dcos.io/binaries/cli/linux/x86-64/dcos-1.10/dcos
	if [[ "$?" != "0" ]]; then echo "Failed to download dcos"; exit 1; fi
	echo "Setting dcos permissions"
	${remote_exec} chmod a+x ./dcos
	if [[ "$?" != "0" ]]; then echo "Failed to chmod dcos"; exit 1; fi
	echo "Configuring dcos"
	${remote_exec} ./dcos cluster setup http://localhost:80
	if [[ "$?" != "0" ]]; then echo "Failed to configure dcos"; exit 1; fi

	# Iterate dnsPrefix
	osTypes=$(jq -r '.properties.agentPoolProfiles[].osType' ${OUTPUT}/apimodel.json)
	oArr=( $osTypes )
	indx=0
	for n in "${oArr[@]}"; do
		dnsPrefix=$(jq -r ".properties.agentPoolProfiles[$indx].dnsPrefix" ${OUTPUT}/apimodel.json)
		if [ "${oArr[$indx]}" = "Windows" ] && [ $dnsPrefix != "null" ]; then
			echo "skipping Windows agent test for $dnsPrefix"
		else
			validate_linux_agent "$dnsPrefix.${LOCATION}.cloudapp.azure.com"
		fi
		indx=$((indx+1))
	done
}

function cleanup() {
	set -x
	echo "cleanup: CLEANUP=${CLEANUP:-}"
	if [[ "${CLEANUP:-}" == "y" ]]; then
		echo "Deleting ${RESOURCE_GROUP}"
		az group delete --no-wait --name="${RESOURCE_GROUP}" --yes || true
	fi
}
