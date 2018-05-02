

# Clone Microsoft/mesos-jenkins repo

    git clone https://github.com/Microsoft/mesos-jenkins.git

# [Install Pester](https://github.com/pester/Pester/wiki/Installation-and-Update) 
Pester is a BDD based test runner, a framework for running Unit Tests to execute and validate PowerShell commands

    Install-Module -Name Pester -Force -SkipPublisherCheck

# [Install and configure Azure PowerShell](https://docs.microsoft.com/en-us/powershell/azure/install-azurerm-ps?view=azurermps-5.1.1)
  
    $ Get-Module PowerShellGet -list | Select-Object Name,Version,Path
    Name          Version Path
    ----          ------- ----
    PowerShellGet 1.0.0.1 C:\Program Files\WindowsPowerShell\Modules\PowerShellGet\1.0.0.1\PowerShellGet.psd1

    $ Install-Module AzureRM -AllowClobber

# [Create a service principal](https://www.terraform.io/docs/providers/azurerm/authenticating_via_service_principal.html)

    $ az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/SUBSCRIPTIONID"
     
        Retrying role assignment creation: 1/36
        {
          "appId": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
          "displayName": "azure-cli-2018-01-30-01-56-30",
          "name": "http://azure-cli-2018-01-30-01-56-30",
          "password": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
          "tenant": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        }


  Note: you  might get the following error this if you are not a owner of your subscription 
  
        $ az ad sp create-for-rbac --role="Contributor" 
                                    --scopes="/subscriptions/xxxxx"
        Role assignment creation failed.

        role assignment response headers: {'Cache-Control': 'no-cache', 
        'Pragma': 'no-cache', 
        'Content-Type': 'application/json; charset=utf-8', 'Expires': '-1', 
        'x-ms-failure-cause': 'gateway',
        'x-ms-request-id': 'xxxxxx',
        'x-ms-correlation-request-id': 'xxxxxx',
        'x-ms-routing-request-id': 'WESTUS2:20180130T015758Z:xxxxxx', 
        'Strict-Transport-Security': 'max-age=31536000; includeSubDomains', 
        'Date': 'Tue, 30 Jan 2018 01:57:58 GMT', 'Connection': 'close', 'Content-Length': '307'}

        The client with object id 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' does not have authorization 
        to perform action 'Microsoft.Authorization/roleAssignments/write' over scope '/subscriptions/....'.


# Create environment variable file

  Add the service principal credential in a file nammed "`.env`" in the following format.
  The unittest case uses this credential to access the Azure subscription for the scaleup and down operations

  Eg.
  
        $Env:CLIENT_ID = value from your service principal's "appId" field
        $Env:CLIENT_SECRET = value from your service principal's "password" field
        $Env:TENANT_ID = value from your service principal's "tenant" field
        $Env:RESOURCE_GROUP = "resource group name"

# Run test script

## Change location to the Pester tests directory
`$ cd <mesos_jenkins_directory_path>\DCOS\autoscale-testing`

## Run all tests
`$ invoke-pester`

## Run a subset of tests:
`$ Invoke-Pester -TestName 'Sanity check'`
