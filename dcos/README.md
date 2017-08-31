The `build-azure-environment.sh` script is used to spawn a DC/OS environment in Azure using some ARM Json deployment templates.

Requirements:
- [Azure CLI 2.0](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Interactively login to Azure with the Azure CLI 2.0 in case the user has 2-way authentication enabled, otherwise the unattended login will fail

Before running the script, some environment variables must be set. These are used as deployment config options by the script:

```
export AZURE_USER="<azure_user>"
export AZURE_USER_PASSWORD="<azure_password_value>"
export AZURE_REGION="West US"
export AZURE_RESOURCE_GROUP="dcos_mesos_rg"

export LINUX_MASTER_VM_SIZE="Standard_D2_v2"
export LINUX_MASTER_DNS_PREFIX="dcos-mstr"
export LINUX_MASTER_ADMIN="azureuser"
export LINUX_MASTER_PUBLIC_SSH_KEY="<public_key_content>"

export WINDOWS_SLAVE_VM_SIZE="Standard_D2_v2"
export WINDOWS_SLAVE_BOOTSTRAP_SRIPT_URL="http://balutoiu.com/ionut/dcos-windows-provision.ps1"
export WINDOWS_MESOS_BINARIES_URL="binaries-url-is-this-aaa"
export WINDOWS_SLAVE_DNS_PREFIX="dcos-slv"
export WINDOWS_SLAVE_ADMIN="azureuser"
export WINDOWS_SLAVE_ADMIN_PASSWORD="<admin_password_value>"
```
