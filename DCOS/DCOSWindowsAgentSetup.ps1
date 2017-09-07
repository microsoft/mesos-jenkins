[CmdletBinding(DefaultParameterSetName="Standard")]
Param(
    [ValidateNotNullOrEmpty()]
    [string]$MasterIP,
    [ValidateNotNullOrEmpty()]
    [string]$AgentPrivateIP,
    [ValidateNotNullOrEmpty()]
    [string]$BootstrapUrl,
    [AllowNull()]
    [switch]$isPublic = $false,
    [AllowNull()]
    [string]$MesosDownloadDir,
    [AllowNull()]
    [string]$MesosInstallDir,
    [AllowNull()]
    [string]$MesosLaunchDir,
    [AllowNull()]
    [string]$MesosWorkDir
)

$ErrorActionPreference = "Stop"

$GIT_INSTALL_DIR = Join-Path $env:ProgramFiles "Git"
$GIT_URL = "http://dcos-win.westus.cloudapp.azure.com/downloads/Git-2.14.1-64-bit.exe"
$MESOS_JENKINS_URL = "https://github.com/ionutbalutoiu/mesos-jenkins" # TODO: Change this to the official repo URL
$MESOS_JENKINS_DIR = Join-Path $env:TEMP "mesos-jenkins"
$MESOS_BINARIES_URL = "$BootstrapUrl/mesos.zip"


function Install-Git {
    if(Test-Path $GIT_INSTALL_DIR) {
        Write-Output "Git is already installed"
        return
    }
    Write-Output "Downloading Git from $GIT_URL"
    $fileName = $GIT_URL.Split('/')[-1]
    $programFile = Join-Path $env:TEMP $fileName
    Remove-Item -Force -Path $programFile -ErrorAction SilentlyContinue
    Invoke-WebRequest -UseBasicParsing -Uri $GIT_URL -OutFile $programFile
    $parameters = @{
        'FilePath' = $programFile
        'ArgumentList' = @("/SILENT")
        'Wait' = $true
        'PassThru' = $true
    }
    Write-Output "Installing $programFile"
    $p = Start-Process @parameters
    if($p.ExitCode -ne 0) {
        Throw "Failed to install Git"
    }
    $env:PATH += ";$GIT_INSTALL_DIR\bin;$GIT_INSTALL_DIR\cmd"
}

function Start-MesosJenkinsClone {
    Remove-Item -Force -Path $MESOS_JENKINS_DIR -ErrorAction SilentlyContinue
    git.exe clone $MESOS_JENKINS_URL $MESOS_JENKINS_DIR
    if($LASTEXITCODE) {
        Throw "Failed to clone $MESOS_JENKINS_URL repository"
    }
}

try {
    Install-Git
    Start-MesosJenkinsClone
    [string[]]$masterAddress = ConvertFrom-Json $MasterIP # We might have a JSON encoded list of master IPs
    & "$MESOS_JENKINS_DIR\DCOS\windows-agent-setup.ps1" -MasterAddress $masterAddress -MesosWindowsBinariesURL $MESOS_BINARIES_URL -AgentPrivateIP $AgentPrivateIP -Public:$isPublic
    if($LASTEXITCODE) {
        Throw "Failed to setup the Mesos Windows agent"
    }
} catch {
    Write-Output $_.ToString()
    exit 1
}
