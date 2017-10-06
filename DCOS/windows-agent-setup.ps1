Param(
    [Parameter(Mandatory=$true)]
    [string]$MesosWindowsBinariesURL,
    [Parameter(Mandatory=$true)]
    [string[]]$MasterAddress,
    [string]$AgentPrivateIP,
    [switch]$Public=$false,
    [string]$CustomAttributes
)


$ErrorActionPreference = "Stop"

$ciUtils = (Resolve-Path "$PSScriptRoot\..\Modules\CIUtils").Path
$globalVariables = (Resolve-Path "$PSScriptRoot\..\global-variables.ps1").Path

Import-Module $ciUtils
. $globalVariables


function New-MesosEnvironment {
    $service = Get-Service $MESOS_SERVICE_NAME -ErrorAction SilentlyContinue
    if($service) {
        Stop-Service -Force -Name $MESOS_SERVICE_NAME
        & sc.exe delete $MESOS_SERVICE_NAME
        if($LASTEXITCODE) {
            Throw "Failed to delete exiting $MESOS_SERVICE_NAME service"
        }
        Write-Output "Deleted existing $MESOS_SERVICE_NAME service"
    }
    New-Directory -RemoveExisting $BOOTSTRAP_TEMP_DIR
    New-Directory -RemoveExisting $MESOS_DIR
    New-Directory -RemoveExisting $MESOS_BIN_DIR
    New-Directory -RemoveExisting $MESOS_WORK_DIR
    New-Directory -RemoveExisting $MESOS_SERVICE_DIR
}

function Install-MesosBinaries {
    $binariesPath = Join-Path $BOOTSTRAP_TEMP_DIR "mesos-binaries.zip"
    Write-Output "Downloading Mesos binaries"
    Invoke-WebRequest -Uri $MesosWindowsBinariesURL -OutFile $binariesPath
    Write-Output "Extracting binaries archive in: $BOOTSTRAP_TEMP_DIR"
    Expand-Archive -LiteralPath $binariesPath -DestinationPath $MESOS_BIN_DIR
}

function Get-MesosAgentAttributes {
    # TODO: Decide what to do with the custom attributes passed from the ACS Engine
    $attributes = "os:windows"
    return $attributes
}

function Get-MesosAgentPrivateIP {
    if($AgentPrivateIP) {
        return $AgentPrivateIP
    }
    $primaryIfIndex = (Get-NetRoute -DestinationPrefix "0.0.0.0/0").ifIndex
    return (Get-NetIPAddress -AddressFamily IPv4 -ifIndex $primaryIfIndex).IPAddress
}

function New-MesosWindowsAgent {
    $mesosBinary = Join-Path $MESOS_BIN_DIR "mesos-agent.exe"
    $agentAddress = Get-MesosAgentPrivateIP
    $mesosAttributes = Get-MesosAgentAttributes
    $mesosAgentArguments = ("--master=`"zk://$($MasterAddress -join ',')/mesos`"" + `
                           " --work_dir=`"${MESOS_WORK_DIR}`"" + `
                           " --runtime_dir=`"${MESOS_WORK_DIR}`"" + `
                           " --launcher_dir=`"${MESOS_BIN_DIR}`"" + `
                           " --log_dir=`"${MESOS_LOG_DIR}`"" + `
                           " --ip=`"${agentAddress}`"" + `
                           " --isolation=`"windows/cpu,filesystem/windows`"" + `
                           " --containerizers=`"docker,mesos`"" + `
                           " --attributes=`"${mesosAttributes}`"")
    $windowsServiceTemplate = @"
<configuration>
  <id>$MESOS_SERVICE_NAME</id>
  <name>Mesos Windows Agent</name>
  <description>Service for Windows Mesos Agent</description>
  <executable>${mesosBinary}</executable>
  <arguments>${mesosAgentArguments}</arguments>
  <logpath>${MESOS_LOG_DIR}</logpath>
  <priority>Normal</priority>
  <stoptimeout>20 sec</stoptimeout>
  <stopparentprocessfirst>false</stopparentprocessfirst>
  <startmode>Automatic</startmode>
  <waithint>15 sec</waithint>
  <sleeptime>1 sec</sleeptime>
  <log mode="roll">
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>8</keepFiles>
  </log>
</configuration>
"@
    Write-Output $windowsServiceTemplate
    $templateFile = Join-Path $MESOS_SERVICE_DIR "mesos-service.xml"
    Set-Content -Path $templateFile -Value $windowsServiceTemplate
    $serviceWapper = Join-Path $MESOS_SERVICE_DIR "mesos-service.exe"
    Invoke-WebRequest -UseBasicParsing -Uri $SERVICE_WRAPPER_URL -OutFile $serviceWapper
    $p = Start-Process -FilePath $serviceWapper -ArgumentList @("install") -NoNewWindow -PassThru -Wait
    if($p.ExitCode -ne 0) {
        Throw "Failed to set up the Mesos Windows service. Exit code: $($p.ExitCode)"
    }
}

function Start-PollingMesosServiceStatus {
    $timeout = 2
    $count = 0
    $maxCount = 10
    while ($count -lt $maxCount) {
        Start-Sleep -Seconds $timeout
        Write-Output "Checking $MESOS_SERVICE_NAME service status"
        $status = (Get-Service -Name $MESOS_SERVICE_NAME).Status
        if($status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
            Throw "Service $MESOS_SERVICE_NAME is not running"
        }
        $count++
    }
}

function Open-MesosFirewallRule {
    Write-Output "Opening Mesos TCP port: $MESOS_AGENT_PORT"
    $name = "Allow inbound TCP Port $MESOS_AGENT_PORT for Mesos"
    $firewallRule = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
    if($firewallRule) {
        Write-Output "Firewall rule already exist"
        return
    }
    return (New-NetFirewallRule -DisplayName $name -Direction Inbound -LocalPort $MESOS_AGENT_PORT -Protocol TCP -Action Allow)
}

function Open-ZookeeperFirewallRule {
    Write-Output "Opening Zookeeper TCP port: $ZOOKEEPER_PORT"
    $name = "Allow inbound TCP Port $ZOOKEEPER_PORT for Zookeeper"
    $firewallRule = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
    if($firewallRule) {
        Write-Output "Firewall rule already exist"
        return
    }
    return (New-NetFirewallRule -DisplayName $name -Direction Inbound -LocalPort $ZOOKEEPER_PORT -Protocol TCP -Action Allow)
}

try {
    New-MesosEnvironment
    Install-MesosBinaries
    New-MesosWindowsAgent
    Start-Service $MESOS_SERVICE_NAME
    Start-PollingMesosServiceStatus
    Open-MesosFirewallRule
    Open-ZookeeperFirewallRule # It's needed on the private DCOS agents
    Set-NetFirewallRule -Name 'FPS-SMB-In-TCP' -Enabled True # The SMB firewall rule is needed when collecting logs
} catch {
    Write-Output $_.ToString()
    exit 1
}

Write-Output "Successfully finished setting up the Windows Mesos Agent"
