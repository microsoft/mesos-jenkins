The `dcos-engine-deploy.sh` script is used to spawn a DC/OS environment in Azure.

Requirements:
- Ubuntu >= 14.04;
- [Azure CLI 2.0](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli);
- Azure service principal account.

Before running the script, some environment variables must be set. These are used as deployment config options by the script:

```
export AZURE_SERVICE_PRINCIPAL_ID="<service_principal_id>"
export AZURE_SERVICE_PRINCIPAL_PASSWORD="<service_principal_password>"
export AZURE_SERVICE_PRINCIPAL_TENAT="<service_principal_tenant>"
export AZURE_REGION="westus"
export AZURE_RESOURCE_GROUP="dcos_mesos_rg"

export LINUX_MASTER_SIZE="Standard_D2_v2"
export LINUX_MASTER_DNS_PREFIX="ib-master"
export LINUX_AGENT_SIZE="Standard_D2_v2"
export LINUX_AGENT_PUBLIC_POOL="iblinpublic"
export LINUX_AGENT_DNS_PREFIX="ib-linagent"
export LINUX_AGENT_PRIVATE_POOL="iblinprivate"
export LINUX_ADMIN="azureuser"
export LINUX_PUBLIC_SSH_KEY="<public_key_content>"

export WIN_AGENT_SIZE="Standard_D2_v2"
export WIN_AGENT_PUBLIC_POOL="ibwinpublic"
export WIN_AGENT_DNS_PREFIX="ib-winagent"
export WIN_AGENT_PRIVATE_POOL="ibwinprivate"
export WIN_AGENT_ADMIN="azureuser"
export WIN_AGENT_ADMIN_PASSWORD="<admin_password_value>"

export DCOS_VERSION="1.10.0"
export DCOS_WINDOWS_BOOTSTRAP_URL="http://dcos-win.westus.cloudapp.azure.com/dcos-windows/stable"
export DCOS_DEPLOYMENT_TYPE="hybrid"
```

The script workflow is the following:

- Generate the necessary ARM JSON templates for the Azure deployment;
- Create the Azure resource group;
- Deploy the DC/OS environment with the Azure CLI 2.0.
