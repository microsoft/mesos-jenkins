#!/bin/bash

set -e
set -u
set -o pipefail

function exit_with_msg {
	echo $1
	exit -1
}

[[ ! -z "${KEYVAULT_NAME:-}" ]]                   || exit_with_msg "Must specify KEYVAULT_NAME"
[[ ! -z "${DCOS_OAUTH_USER_SECRET_NAME:-}" ]]     || exit_with_msg "Must specify DCOS_OAUTH_USER_SECRET_NAME"
[[ ! -z "${DCOS_OAUTH_PASSWORD_SECRET_NAME:-}" ]] || exit_with_msg "Must specify DCOS_OAUTH_PASSWORD_SECRET_NAME"
[[ ! -z "${RESOURCE_GROUP:-}" ]]                  || exit_with_msg "Must specify RESOURCE_GROUP"
[[ ! -z "${NAMESUFFIX:-}" ]]                      || exit_with_msg "Must specify NAMESUFFIX"
[[ ! -z "${SSH_KEY:-}" ]]                         || exit_with_msg "Must specify SSH_KEY"

which az           || exit_with_msg "az must be on PATH"
which chromedriver || exit_with_msg "chromedriver must be on PATH"

export DCOS_OAUTH_USER=$(az keyvault secret show --vault-name ${KEYVAULT_NAME} --name ${DCOS_OAUTH_USER_SECRET_NAME} | jq -r .value)
export DCOS_OAUTH_PASSWORD=$(az keyvault secret show --vault-name ${KEYVAULT_NAME} --name ${DCOS_OAUTH_PASSWORD_SECRET_NAME} | jq -r .value)

publicIpId=$(az network lb show -g ${RESOURCE_GROUP} -n dcos-master-lb-$NAMESUFFIX --query "frontendIpConfigurations[].publicIpAddress.id" --out tsv)
masterIp=$(az network public-ip show --ids "${publicIpId}" --query "{ ipAddress: ipAddress }" --out tsv)

# start SSH tunnel
ssh -i ${SSH_KEY} -L 12345:localhost:80 -p 2200 azureuser@${masterIp} sleep 30 &

# get Open ID Connect token and login to DC/OS
export DCOS_URL="http://localhost:12345"
token=$(python get_dcos_oidc_token_chrome.py)

# stop SSH tunnel
kill %% || echo "skipped"

# copy token to the master
tmpfile=$(mktemp)
trap "rm -f $tmpfile" EXIT
echo $token | cat > $tmpfile
scp -i ${SSH_KEY} -P 2200 $tmpfile azureuser@${masterIp}:~/.dcos.oidc.token
echo "Token copied"
