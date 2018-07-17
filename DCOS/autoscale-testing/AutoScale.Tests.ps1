Import-Module AzureRM

$here = Split-Path -Parent $MyInvocation.MyCommand.Path


function Set-CredentialsFromEnvFile {
    if (Test-Path "${here}\env.ps1") {
        . "${here}\env.ps1"
    } else {
        Throw "ERROR: Could not find ${here}\env.ps1 file to source credentials. Please create it."
    }
}

function Confirm-CredentialsEnvVariables {
    if(!$env:CLIENT_ID) {
        Throw "ERROR: CLIENT_ID is not set"
    }
    if(!$env:CLIENT_SECRET) {
        Throw "ERROR: CLIENT_SECRET is not set"
    }
    if(!$env:TENANT_ID) {
        Throw "ERROR: TENANT_ID is not set"
    }
}

function New-AzureRmSession {
    try {
        $subscription = Get-AzureRmSubscription
    } catch {
        $subscription = $null
    }
    if($subscription) {
        # Disconnect any account if it's logged
        Remove-AzureRmAccount -Confirm:$false
    }
    if(!$env:CLIENT_ID -or !$env:CLIENT_SECRET -or !$env:TENANT_ID) {
        Set-CredentialsFromEnvFile
    }
    Confirm-CredentialsEnvVariables
    $securePass = ConvertTo-SecureString $env:CLIENT_SECRET -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $env:CLIENT_ID, $securePass
    Connect-AzureRmAccount -Credential $cred -ServicePrincipal -TenantId $env:TENANT_ID
}

function Get-ScaleSetsVMsCount {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName
    )
    $vmsCount = 0
    $scaleSets = Get-AzureRmVmss -ResourceGroupName $ResourceGroupName -WarningAction Ignore
    $scaleSets | ForEach-Object {
        $vms = Get-AzureRmVmssVM -ResourceGroupName $ResourceGroupName -VMScaleSetName $_.Name
        $vmsCount += $vms.Count
    }
    return $vmsCount
}

function Get-MasterFQDN {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName
    )
    $deployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName
    return $deployment.Outputs.masterFQDN.Value
}

function Get-DCOSAgentsCount {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName
    )
    $masterFQDN = Get-MasterFQDN $ResourceGroupName
    $res = Invoke-WebRequest -UseBasicParsing -Uri "http://${masterFQDN}/dcos-history-service/history/last" | ConvertFrom-Json | Select-Object "slaves"
    return $res.slaves.Count
}

function Confirm-DCOSAgentsHealth {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName
    )
    $masterFQDN = Get-MasterFQDN $ResourceGroupName
    $res = Invoke-WebRequest -UseBasicParsing -Uri "http://${masterFQDN}/system/health/v1/nodes" | ConvertFrom-Json | Select-Object "nodes"
    $allHealthy = $true
    foreach ($agentNode in $res.nodes) {
        if ($agentNode.health -eq 0) {
            continue
        }
        $allHealthy = $false
        Write-Host "Unhealthy node detected: host_ip = $($agentNode.host_ip) ; role = $($agentNode.role) ; health = $($agentNode.health)"
    }
    return $allHealthy
}

function Confirm-DCOSAgentsGoodMetrics {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName
    )
    $mesosAuth = Confirm-MesosAuthentication
    if($mesosAuth) {
        Throw "Mesos authentication is enabled. dcos-metrics doesn't with with this feature enabled."
    }
    $masterFQDN = Get-MasterFQDN $ResourceGroupName
    $res = Invoke-WebRequest -UseBasicParsing -Uri "http://${masterFQDN}/dcos-history-service/history/last" | ConvertFrom-Json | Select-Object "slaves"
    $allMetricsGood = $true
    foreach ($agentNode in $res.slaves) {
        try {
            $res = Invoke-WebRequest -UseBasicParsing -Uri "http://${masterFQDN}/system/v1/agent/$($agentNode.id)/metrics/v0/node" | ConvertFrom-Json
            $dataPointCount = $res.datapoints.Count
            if ($dataPointCount -eq 0) {
                Write-Host "Got no datapoints back. Something is wrong with the dcos-metrics service"
                Write-Host "agentNode.attributes.os = $($agentNode.attributes.os) ; agentNode.id = $($agentNode.id) ; agentNode.hostname = $($agentNode.hostname) ; dataPointCount = $dataPointCount"
                $allMetricsGood = $false
            }
        } catch {
            Write-Host $_.Exception.Message
            Write-Host "Metrics query failed on agent: hostname = $($agentNode.hostname) ; osType = $($agentNode.attributes.os) ; id = $($agentNode.id)"
            $allMetricsGood = $false
        }
    }
    return $allMetricsGood
}

function Confirm-MesosAuthentication {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName
    )
    $masterFQDN = Get-MasterFQDN $ResourceGroupName
    $res = Invoke-WebRequest -UseBasicParsing -Uri "http://${masterFQDN}/mesos/flags" | ConvertFrom-Json
    return ($res.flags.authenticate_agents -eq "true")
}


#
# Create an AzureRM session
#
New-AzureRmSession


#
# Execute the Pester integration tests
#
Describe "Sanity check" {

    It "Is logged in to Azure" {
        $subscription = Get-AzureRmSubscription
        $subscription | Should not be $null
    }

    It "Has a resource group defined" {
        $env:RESOURCE_GROUP | Should not be $null
    }
}

Describe "Initial check" {

    It "Can get scalesets" {
        $env:RESOURCE_GROUP | Should not be $null
        $scaleSets = Get-AzureRmVmss -ResourceGroupName $env:RESOURCE_GROUP -WarningAction Ignore
        $scaleSets | Should not be $null
        $scaleSets.Count | Should BeGreaterThan 0
    }

    It "Can get scaleset OS" {
        $scaleSets = Get-AzureRmVmss -ResourceGroupName $env:RESOURCE_GROUP -WarningAction Ignore
        $scaleSets | Should not be $null
        $scaleSets.Count | Should BeGreaterThan 0
        $scaleSets | ForEach-Object {
            $os = $_.VirtualMachineProfile.OsProfile
            $os.WindowsConfiguration -or $os.LinuxConfiguration | Should not be $false
            if ($os.WindowsConfiguration){
                $os.LinuxConfiguration | Should be $null
            }
            if ($os.LinuxConfiguration){
                $os.WindowsConfiguration | Should be $null
            }
        }
    }

    It "Can get scaleset VMs" {
        $scaleSets = Get-AzureRmVmss -ResourceGroupName $env:RESOURCE_GROUP -WarningAction Ignore
        $scaleSets | Should not be $null
        $scaleSets.Count | Should BeGreaterThan 0
        $scaleSets | ForEach-Object {
            $vms = Get-AzureRmVmssVM -ResourceGroupName $env:RESOURCE_GROUP -VMScaleSetName $_.Name
            $vms | Should not be $null
            $vms.Count | Should BeGreaterThan 0
        }
    }

    It "Can get DCOS" {
        # If you want to manage the DCOS master remotely you will need to add an inbound NAT rule to open
        # port 80 for the master load balancer and inbound rule for the master network security group.
        $deployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $env:RESOURCE_GROUP
        $deployment | Should not be $null
        
        $masterFQDN = $deployment.Outputs.masterFQDN.Value
        $masterFQDN | Should not be $null
        
        $res = Invoke-WebRequest -UseBasicParsing -Uri "http://$masterFQDN/dcos-history-service/history/last" | ConvertFrom-Json | Select-Object slaves
        $res | Should not be $null
        $res.slaves | Should not be $null
        $res.slaves.Count | Should BeGreaterThan 0
    }

    It "Has the expected number of instances in DCOS" {
        $env:RESOURCE_GROUP | Should not be $null
        Get-ScaleSetsVMsCount $env:RESOURCE_GROUP | Should be $(Get-DCOSAgentsCount $env:RESOURCE_GROUP)
    }

    It "Are all nodes healthy" {
        Confirm-DCOSAgentsHealth -ResourceGroupName $env:RESOURCE_GROUP | Should be $true
    }

    $mesosAuth = Confirm-MesosAuthentication -ResourceGroupName $env:RESOURCE_GROUP
    # Skip metrics tests if Mesos authentication is enabled
    $skipFlag = $mesosAuth

    It "Are all nodes metric service running fine" -Skip:$skipFlag {
        Confirm-DCOSAgentsGoodMetrics -ResourceGroupName $env:RESOURCE_GROUP | Should be $true
    }
}

Describe "Scale up check" {
    $testCases = @()
    $scaleSets = Get-AzureRmVmss -ResourceGroupName $env:RESOURCE_GROUP -WarningAction Ignore
    $scaleSets | Foreach-Object {$testCases += @{scaleset = $_}}

    It "Can increase the scaleset capacity ${scaleset}" -TestCases $testCases {
        Param($scaleset)

        Write-Host "Testing vmss: $($scaleset.Name)"
        $initialCapacity = $scaleset.Sku.Capacity

        # Make sure we are initially scaled down (1 or 2 vms)
        $initialCapacity | Should BeLessThan 3

        # Scale up
        $scaleset.Sku.capacity = 4
        $res = Update-AzureRmVmss -ResourceGroupName $env:RESOURCE_GROUP -Name $scaleset.Name -VirtualMachineScaleSet $scaleset -WarningAction Ignore
        $res | Should not be $null
        $res.Sku.Capacity | Should be 4

        # Sanity check
        $updatedVmss = Get-AzureRmVmss -ResourceGroupName $env:RESOURCE_GROUP -VMScaleSetName $scaleset.Name -WarningAction Ignore
        $updatedVmss.Sku.Capacity | Should be 4
    }

    $mesosAuth = Confirm-MesosAuthentication -ResourceGroupName $env:RESOURCE_GROUP
    # New Linux agents added after scale-up won't have dcos-metrics disabled.
    # If Mesos authentication is enabled, besides metrics tests, we skip
    # the nodes health check tests.
    $skipFlag = $mesosAuth

    It "Are all nodes healthy" -Skip:$skipFlag {
        Confirm-DCOSAgentsHealth -ResourceGroupName $env:RESOURCE_GROUP | Should be $true
    }

    It "Are all nodes metric service running fine" -Skip:$skipFlag {
        Confirm-DCOSAgentsGoodMetrics -ResourceGroupName $env:RESOURCE_GROUP | Should be $true
    }
}

Describe "DC/OS API check" {
    It "Reports the same amount of agents as the number of VMs in the scalesets" {
        $env:RESOURCE_GROUP | Should not be $null

        $vmCount = Get-ScaleSetsVMsCount $env:RESOURCE_GROUP
        $agentCount = Get-DCOSAgentsCount $env:RESOURCE_GROUP
        $retryCount = 15
        do {
            if ($vmCount -eq $agentCount){
                break
            }
            Start-Sleep -Seconds 60
            $agentCount = Get-DCOSAgentsCount $env:RESOURCE_GROUP
            Write-Host "Retry count=$retryCount VMs=$vmCount agents=$agentCount"
            $retryCount -= 1
        } while($retryCount -gt 0)
        $agentCount | Should Be $vmCount
    }
}

Describe "Scale down check" {
    $testCases = @()
    $scaleSets = Get-AzureRmVmss -ResourceGroupName $env:RESOURCE_GROUP -WarningAction Ignore
    $scaleSets | Foreach-Object {$testCases += @{scaleset = $_}}

    It "Can reduce the scaleset capacity" -TestCases $testCases {
        Param($scaleset)

        Write-Host "Testing vmss: $($scaleset.Name)"
        $initialCapacity = $scaleset.Sku.Capacity

        # Make sure we are initially scaled up 3 or more
        $initialCapacity | Should BeGreaterThan 2

        # Scale down to 2
        $scaleset.Sku.capacity = 2
        $res = Update-AzureRmVmss -ResourceGroupName $env:RESOURCE_GROUP -Name $scaleset.Name -VirtualMachineScaleSet $scaleset -WarningAction Ignore
        $res | Should not be $null
        $res.Sku.Capacity | Should be 2

        # Sanity check
        $updatedVmss = Get-AzureRmVmss -ResourceGroupName $env:RESOURCE_GROUP -VMScaleSetName $scaleset.Name -WarningAction Ignore
        $updatedVmss.Sku.Capacity | Should be 2
    }

    $mesosAuth = Confirm-MesosAuthentication -ResourceGroupName $env:RESOURCE_GROUP
    # New Linux agents added after scale-up won't have dcos-metrics disabled.
    # After scale-down, we might be in the situation that some of the nodes
    # left are the new agents added in the scale-up phase with dcos-metrics
    # enabled. If Mesos authentication is enabled, besides metrics tests, we
    # skip the nodes health check tests.
    $skipFlag = $mesosAuth

    It "Are all nodes healthy" -Skip:$skipFlag {
        Confirm-DCOSAgentsHealth -ResourceGroupName $env:RESOURCE_GROUP | Should be $true
    }

    It "Are all nodes metric service running fine" -Skip:$skipFlag {
        Confirm-DCOSAgentsGoodMetrics -ResourceGroupName $env:RESOURCE_GROUP | Should be $true
    }
}
