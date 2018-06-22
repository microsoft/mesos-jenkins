#!/usr/bin/env bash

DIR=$(dirname $0)

if [[ -z $WORKSPACE ]]; then
    echo "ERROR: The environment variable WORKSPACE is not set"
    exit 1
fi

echo "Starting time: $(date)"

# - Install latest ACS Engine internal stable build
ACS_ENGINE_URL="http://dcos-win.westus.cloudapp.azure.com/acs-engine/stable-candidate/latest/linux-amd64/acs-engine"
mkdir -p $WORKSPACE/bin && \
curl $ACS_ENGINE_URL -o $WORKSPACE/bin/acs-engine && \
chmod +x $WORKSPACE/bin/acs-engine && \
export PATH="$WORKSPACE/bin:$PATH" 
check_exit_code false

# - Source the the DC/OS e2e functions
source $DIR/dcos-testing.sh

# - Login to Azure
azure_cli_login
check_exit_code false

# - Generate Linux SSH keypair
get_linux_ssh_keypair
check_exit_code false

# - Generate a Windows password to be used
get_windows_password
check_exit_code false

# - Deploy DC/OS master + slave nodes
$DIR/acs-engine-dcos-deploy.sh
check_exit_code false

# - Open DC/OS API & GUI port
open_dcos_port
check_exit_code true

# - Create the testing environment
create_testing_environment
check_exit_code true

# - Run the functional tests
run_functional_tests
check_exit_code true

# - Run fluentd tests
run_fluentd_tests
check_exit_code true

# - Run the autoscale testing
run_dcos_autoscale_job
check_exit_code true

# - Successfully exit the job
successfully_exit_dcos_testing_job
