Param(
    [Parameter(Mandatory=$true)]
    [string]$DCOSWindowsBinariesURL,
    [Parameter(Mandatory=$true)]
    [string]$MasterIP
)

$ErrorActionPreference = "Stop"

$SERVICE_WRAPPER_URL = 'http://104.210.40.105/downloads/WinSW.NET4.exe'
$BOOTSTRAP_TEMP_DIR = Join-Path $env:Temp "DCOS_Bootstrap"
$MESOS_DIR = Join-Path $env:SystemDrive "mesos"
$MESOS_BIN_DIR = Join-Path $MESOS_DIR "bin"
$MESOS_WORK_DIR = Join-Path $MESOS_DIR "work"
$MESOS_LOG_DIR = Join-Path $MESOS_DIR "log"
$MESOS_SERVICE_DIR = Join-Path $MESOS_DIR "service"
$MESOS_AGENT_PORT = 5051
$MESOS_SERVICE_NAME = "mesos-agent"


function New-Directory {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    if(Test-Path $Path) {
        # Remove if it already exist
        Remove-Item -Recurse -Force $Path
    }
    return (New-Item -ItemType Directory -Path $Path)
}

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
    New-Directory $BOOTSTRAP_TEMP_DIR
    New-Directory $MESOS_DIR
    New-Directory $MESOS_BIN_DIR
    New-Directory $MESOS_WORK_DIR
    New-Directory $MESOS_SERVICE_DIR
}

function Install-MesosBinaries {
    $binariesPath = Join-Path $BOOTSTRAP_TEMP_DIR "mesos-binaries.zip"
    Write-Output "Downloading Mesos binaries"
    Invoke-WebRequest -Uri $DCOSWindowsBinariesURL -OutFile $binariesPath
    Write-Output "Extracting binaries archive in: $BOOTSTRAP_TEMP_DIR"
    Expand-Archive -LiteralPath $binariesPath -DestinationPath $MESOS_BIN_DIR
}

function New-MesosWindowsAgent {
    (Get-NetRoute -DestinationPrefix "0.0.0.0/0").ifIndex
    $agentAddress = (Get-NetIPAddress -AddressFamily IPv4 -ifIndex (Get-NetRoute -DestinationPrefix "0.0.0.0/0").ifIndex).IPAddress
    $mesosBinary = Join-Path $MESOS_BIN_DIR "mesos-agent.exe"
    $windowsServiceTemplate = @"
<configuration>
  <id>$MESOS_SERVICE_NAME</id>
  <name>Mesos Windows Agent</name>
  <description>Service for Windows Mesos Agent</description>
  <executable>${mesosBinary}</executable>
  <arguments>--master=zk://${MasterIP}:2181/mesos --work_dir=${MESOS_WORK_DIR} --runtime_dir=${MESOS_WORK_DIR} --launcher_dir=${MESOS_BIN_DIR} --isolation=windows/cpu,filesystem/windows --ip=${agentAddress} --containerizers=docker,mesos --log_dir=${MESOS_LOG_DIR}\</arguments>
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

try {
    New-MesosEnvironment
    Install-MesosBinaries
    New-MesosWindowsAgent
    Start-Service $MESOS_SERVICE_NAME
    Start-PollingMesosServiceStatus
    Open-MesosFirewallRule
} catch {
    Write-Output $_
    exit 1
}

Write-Output "Successfully finished setting up the Windows Mesos Agent"
