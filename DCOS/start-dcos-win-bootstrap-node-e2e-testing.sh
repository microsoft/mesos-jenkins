#!/usr/bin/env bash

DIR=$(dirname $0)

if [[ -z $WORKSPACE ]]; then
    echo "ERROR: The environment variable WORKSPACE is not set"
    exit 1
fi

if [[ -z $MASTER_WHITELISTED_IPS ]]; then
    echo "ERROR: The environment variable MASTER_WHITELISTED_IPS is not set."
    exit 1
fi

echo "Starting time: $(date)"

# - Source the the DC/OS e2e functions
source $DIR/dcos-testing.sh

# - Install latest DCOS Engine internal stable build
mkdir -p $WORKSPACE/bin && \
curl -L -s --retry 30 "http://dcos-win.westus2.cloudapp.azure.com/dcos-engine/stable-candidate/master/latest/linux-amd64/dcos-engine" -o $WORKSPACE/bin/dcos-engine && \
chmod +x $WORKSPACE/bin/dcos-engine && \
export PATH="$WORKSPACE/bin:$PATH"
check_exit_code false

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
$DIR/dcos-engine-deploy.sh
check_exit_code false

# - Open DC/OS API & GUI port
open_dcos_port
check_exit_code true

# - Create the testing environment
create_testing_environment
check_exit_code true

# - Run the functional tests (for deployments with Windows bootstrap node)
run_win_bootstrap_node_functional_tests
check_exit_code true

# - Run fluentd tests
run_fluentd_tests
check_exit_code true

# - Run the scalability testing
run_dcos_scalability_job
check_exit_code true

# - Successfully exit the job
successfully_exit_dcos_testing_job
