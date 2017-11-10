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


$TEMPLATES_DIR = Join-Path $PSScriptRoot "templates"


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
    New-Directory -RemoveExisting $MESOS_DIR
    New-Directory $MESOS_BIN_DIR
    New-Directory $MESOS_WORK_DIR
    New-Directory $MESOS_SERVICE_DIR
}

function Install-MesosBinaries {
    $binariesPath = Join-Path $env:TEMP "mesos-binaries.zip"
    Write-Output "Downloading Mesos binaries"
    Invoke-WebRequest -Uri $MesosWindowsBinariesURL -OutFile $binariesPath
    Write-Output "Extracting binaries archive in: $MESOS_BIN_DIR"
    Expand-Archive -LiteralPath $binariesPath -DestinationPath $MESOS_BIN_DIR
    Remove-item $binariesPath
}

function Get-MesosAgentAttributes {
    $attributes = "os:windows"
    if($Public) {
        $attributes += ";public_ip:yes"
    }
    # TODO: Decide what to do with the custom attributes passed from the ACS Engine
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
    $masterZkAddress = "zk://" + ($MasterAddress -join ":2181,") + ":2181/mesos"
    $mesosAgentArguments = ("--master=`"${masterZkAddress}`"" + `
                           " --work_dir=`"${MESOS_WORK_DIR}`"" + `
                           " --runtime_dir=`"${MESOS_WORK_DIR}`"" + `
                           " --launcher_dir=`"${MESOS_BIN_DIR}`"" + `
                           " --log_dir=`"${MESOS_LOG_DIR}`"" + `
                           " --ip=`"${agentAddress}`"" + `
                           " --isolation=`"windows/cpu,filesystem/windows`"" + `
                           " --containerizers=`"docker,mesos`"" + `
                           " --attributes=`"${mesosAttributes}`"")
    if($Public) {
        $mesosAgentArguments += " --default_role=`"slave_public`""
    }
    $context = @{
        "service_name" = $MESOS_SERVICE_NAME
        "service_display_name" = "DCOS Mesos Windows Slave"
        "service_description" = "Windows Service for the DCOS Mesos Slave"
        "service_binary" = $mesosBinary
        "service_arguments" = $mesosAgentArguments
        "log_dir" = $MESOS_LOG_DIR
    }
    Start-RenderTemplate -TemplateFile "$TEMPLATES_DIR\windows-service.xml" -Context $context -OutFile "$MESOS_SERVICE_DIR\mesos-service.xml"
    $serviceWapper = Join-Path $MESOS_SERVICE_DIR "mesos-service.exe"
    Invoke-WebRequest -UseBasicParsing -Uri $SERVICE_WRAPPER_URL -OutFile $serviceWapper
    $p = Start-Process -FilePath $serviceWapper -ArgumentList @("install") -NoNewWindow -PassThru -Wait
    if($p.ExitCode -ne 0) {
        Throw "Failed to set up the DCOS Mesos Slave Windows service. Exit code: $($p.ExitCode)"
    }
    Start-ExternalCommand { sc.exe failure $MESOS_SERVICE_NAME reset=5 actions=restart/1000 }
    Start-ExternalCommand { sc.exe failureflag $MESOS_SERVICE_NAME 1 }
    Start-Service $MESOS_SERVICE_NAME
}

try {
    New-MesosEnvironment
    Install-MesosBinaries
    New-MesosWindowsAgent
    Open-WindowsFirewallRule -Name "Allow inbound TCP Port $MESOS_AGENT_PORT for Mesos Slave" -Direction "Inbound" -LocalPort $MESOS_AGENT_PORT -Protocol "TCP"
    Open-WindowsFirewallRule -Name "Allow inbound TCP Port $ZOOKEEPER_PORT for Zookeeper" -Direction "Inbound" -LocalPort $ZOOKEEPER_PORT -Protocol "TCP" # It's needed on the private DCOS agents
} catch {
    Write-Output $_.ToString()
    exit 1
}
Write-Output "Successfully finished setting up the Windows Mesos Agent"
exit 0
