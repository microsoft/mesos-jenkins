#!/usr/bin/env bash
set -e

CI_WEB_ROOT="http://dcos-win.westus.cloudapp.azure.com"


validate_simple_deployment_params() {
    if [[ -z $AZURE_SERVICE_PRINCIPAL_ID ]]; then echo "ERROR: Parameter AZURE_SERVICE_PRINCIPAL_ID is not set"; exit 1; fi
    if [[ -z $AZURE_SERVICE_PRINCIPAL_PASSWORD ]]; then echo "ERROR: Parameter AZURE_SERVICE_PRINCIPAL_PASSWORD is not set"; exit 1; fi
    if [[ -z $AZURE_SERVICE_PRINCIPAL_TENAT ]]; then echo "ERROR: Parameter AZURE_SERVICE_PRINCIPAL_TENAT is not set"; exit 1; fi
    if [[ -z $AZURE_REGION ]]; then echo "ERROR: Parameter AZURE_REGION is not set"; exit 1; fi
    if [[ -z $AZURE_RESOURCE_GROUP ]]; then echo "ERROR: Parameter AZURE_RESOURCE_GROUP is not set"; exit 1; fi

    if [[ -z $LINUX_MASTER_SIZE ]]; then echo "ERROR: Parameter LINUX_MASTER_SIZE is not set"; exit 1; fi
    if [[ -z $LINUX_MASTER_DNS_PREFIX ]]; then echo "ERROR: Parameter LINUX_MASTER_DNS_PREFIX is not set"; exit 1; fi
    if [[ -z $LINUX_ADMIN ]]; then echo "ERROR: Parameter LINUX_ADMIN is not set"; exit 1; fi
    if [[ -z $LINUX_PUBLIC_SSH_KEY ]]; then echo "ERROR: Parameter LINUX_PUBLIC_SSH_KEY is not set"; exit 1; fi

    if [[ -z $WIN_AGENT_SIZE ]]; then echo "ERROR: Parameter WIN_AGENT_SIZE is not set"; exit 1; fi
    if [[ -z $WIN_AGENT_PUBLIC_POOL ]]; then echo "ERROR: Parameter WIN_AGENT_PUBLIC_POOL is not set"; exit 1; fi
    if [[ -z $WIN_AGENT_DNS_PREFIX ]]; then echo "ERROR: Parameter WIN_AGENT_DNS_PREFIX is not set"; exit 1; fi
    if [[ -z $WIN_AGENT_ADMIN ]]; then echo "ERROR: Parameter WIN_AGENT_ADMIN is not set"; exit 1; fi
    if [[ -z $WIN_AGENT_ADMIN_PASSWORD ]]; then echo "ERROR: Parameter WIN_AGENT_ADMIN_PASSWORD is not set"; exit 1; fi

    if [[ ! -z $DCOS_VERSION ]] && [[ "$DCOS_VERSION" != "1.8.8" ]] && [[ "$DCOS_VERSION" != "1.9.0" ]] && [[ "$DCOS_VERSION" != "1.10.0" ]] && [[ "$DCOS_VERSION" != "1.11.0" ]]; then
        echo "ERROR: Supported DCOS_VERSION are: 1.8.8, 1.9.0, 1.10.0 or 1.11.0"
        exit 1
    fi
    if [[ -z $DCOS_WINDOWS_BOOTSTRAP_URL ]]; then
        export DCOS_WINDOWS_BOOTSTRAP_URL="$CI_WEB_ROOT/dcos-windows/testing/windows-agent-blob/latest"
    fi
    if [[ -z $DCOS_BOOTSTRAP_URL ]]; then
        export DCOS_BOOTSTRAP_URL="https://downloads.dcos.io/dcos/testing/pull/2481/dcos_generate_config.sh"
    fi
}

validate_extra_hybrid_deployment_params() {
    if [[ -z $LINUX_AGENT_SIZE ]]; then echo "ERROR: Parameter LINUX_AGENT_SIZE is not set"; exit 1; fi
    if [[ -z $LINUX_AGENT_PUBLIC_POOL ]]; then echo "ERROR: Parameter LINUX_AGENT_PUBLIC_POOL is not set"; exit 1; fi
    if [[ -z $LINUX_AGENT_DNS_PREFIX ]]; then echo "ERROR: Parameter LINUX_AGENT_DNS_PREFIX is not set"; exit 1; fi
    if [[ -z $LINUX_AGENT_PRIVATE_POOL ]]; then echo "ERROR: Parameter LINUX_AGENT_PRIVATE_POOL is not set"; exit 1; fi

    if [[ -z $WIN_AGENT_PRIVATE_POOL ]]; then echo "ERROR: Parameter WIN_AGENT_PRIVATE_POOL is not set"; exit 1; fi
}

validate_prerequisites() {
    for TOOL in az dcos-engine; do
        which $TOOL > /dev/null || {
            echo "ERROR: Couldn't find $TOOL in PATH"
            exit 1
        }
    done
}

azure_cli_login() {
    if az account list --output json | jq -r '.[0]["user"]["name"]' | grep -q "^${AZURE_SERVICE_PRINCIPAL_ID}$"; then
        echo "Account is already logged"
        return
    fi
    az login --output table --service-principal -u $AZURE_SERVICE_PRINCIPAL_ID -p $AZURE_SERVICE_PRINCIPAL_PASSWORD --tenant $AZURE_SERVICE_PRINCIPAL_TENAT
}

# Check if all parameters are set
if [[ -z $DCOS_DEPLOYMENT_TYPE ]]; then echo "ERROR: Parameter DCOS_DEPLOYMENT_TYPE is not set"; exit 1; fi
validate_simple_deployment_params
if [[ "$DCOS_DEPLOYMENT_TYPE" = "hybrid" ]]; then
    validate_extra_hybrid_deployment_params
fi

# Check if all the prerequisites are installed
validate_prerequisites

BASE_DIR=$(dirname $0)
TEMPLATES_DIR="$BASE_DIR/templates"


# Generate the Azure ARM deploy files
if [[ ! -z $DCOS_VERSION ]]; then
    DCOS_TEMPLATE="$TEMPLATES_DIR/dcos-engine/stable/${DCOS_DEPLOYMENT_TYPE}.json"
else
    DCOS_TEMPLATE="$TEMPLATES_DIR/dcos-engine/testing/${DCOS_DEPLOYMENT_TYPE}.json"
fi
if [[ -z $DCOS_DEPLOY_DIR ]]; then
    DCOS_DEPLOY_DIR=$(mktemp -d -t "dcos-deploy-XXXXXXXXXX")
else
    mkdir -p $DCOS_DEPLOY_DIR
fi
DCOS_RENDERED_TEMPLATE="${DCOS_DEPLOY_DIR}/dcos-engine-template.json"
eval "cat << EOF
$(cat $DCOS_TEMPLATE)
EOF
" > $DCOS_RENDERED_TEMPLATE
dcos-engine generate --output-directory $DCOS_DEPLOY_DIR $DCOS_RENDERED_TEMPLATE
rm -rf ./translations # Left-over after running 'dcos-engine generate'

if [[ ! -z $BUILD_ARTIFACTS_DIR ]] && [[ -d $BUILD_ARTIFACTS_DIR ]]; then
    cp -rf $DCOS_DEPLOY_DIR ${BUILD_ARTIFACTS_DIR}/
fi

# Deploy the DC/OS with Mesos environment
DEPLOY_TEMPLATE_FILE="$DCOS_DEPLOY_DIR/azuredeploy.json"
DEPLOY_PARAMS_FILE="$DCOS_DEPLOY_DIR/azuredeploy.parameters.json"

azure_cli_login
EXTRA_PARAMS=""
if [[ "$DEBUG" = "true" ]]; then
    EXTRA_PARAMS="$EXTRA_PARAMS --debug"
fi
if [[ "$VERBOSE" = "true" ]]; then
    EXTRA_PARAMS="$EXTRA_PARAMS --verbose"
fi
CLEANUP_TAG=""
if [[ "$SET_CLEANUP_TAG" = "true" ]]; then
    CLEANUP_TAG="--tags now=$(date +%s)"
fi
az group create -l "$AZURE_REGION" -n "$AZURE_RESOURCE_GROUP" -o table $TAGS $EXTRA_PARAMS $CLEANUP_TAG
echo "Validating the DC/OS ARM deployment templates"
az group deployment validate -g "$AZURE_RESOURCE_GROUP" --template-file $DEPLOY_TEMPLATE_FILE --parameters @$DEPLOY_PARAMS_FILE -o table $EXTRA_PARAMS
echo "Started the DC/OS deployment"
az group deployment create -g "$AZURE_RESOURCE_GROUP" --template-file $DEPLOY_TEMPLATE_FILE --parameters @$DEPLOY_PARAMS_FILE -o table $EXTRA_PARAMS
rm -rf $DCOS_DEPLOY_DIR
