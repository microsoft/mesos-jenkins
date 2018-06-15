#!/bin/bash

set -e

#TODO check variables are set

export DCOS_OAUTH_USER=$(az keyvault secret show --vault-name ${KEYVAULT_NAME} --name ${DCOS_OAUTH_USER_SECRET_NAME} | jq -r .value)
export DCOS_OAUTH_PASSWORD=$(az keyvault secret show --vault-name ${KEYVAULT_NAME} --name ${DCOS_OAUTH_PASSWORD_SECRET_NAME} | jq -r .value)

publicIpId=$(az network lb show -g ${RESOURCE_GROUP} -n dcos-master-lb-$NAMESUFFIX --query "frontendIpConfigurations[].publicIpAddress.id" --out tsv)
export DCOS_HOSTNAME=$(az network public-ip show --ids "${publicIpId}" --query "{ ipAddress: ipAddress }" --out tsv)

#TODO : set up tunnel

token=$(python get_dcos_oidc_token_chrome.py)

echo $token | dcos cluster setup http://${DCOS_HOSTNAME}

echo "Authentication completed"
