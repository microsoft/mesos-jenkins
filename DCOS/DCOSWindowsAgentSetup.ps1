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
    [string]$MesosWorkDir,
    [AllowNull()]
    [string]$customAttrs
)

$ErrorActionPreference = "Stop"

$MESOS_JENKINS_URL = "https://github.com/ionutbalutoiu/mesos-jenkins" # TODO: Change this to the official repo URL
$MESOS_JENKINS_DIR = Join-Path $env:TEMP "mesos-jenkins"
$MESOS_BINARIES_URL = "$BootstrapUrl/mesos.zip"


function Add-ToSystemPath {
    Param(
        [Parameter(Mandatory=$true)]
        [string[]]$Path
    )
    $systemPath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine').Split(';')
    $currentPath = $env:PATH.Split(';')
    foreach($p in $Path) {
        if($p -notin $systemPath) {
            $systemPath += $p
        }
        if($p -notin $currentPath) {
            $currentPath += $p
        }
    }
    $env:PATH = $currentPath -join ';'
    setx.exe /M PATH ($systemPath -join ';')
    if($LASTEXITCODE) {
        Throw "Failed to set the new system path"
    }
}

function Install-Prerequisites {
    $prerequisites = @{
        'git'= @{
            'url'= "http://dcos-win.westus.cloudapp.azure.com/downloads/Git-2.14.1-64-bit.exe"
            'install_args' = @("/SILENT")
            'install_dir' = (Join-Path $env:ProgramFiles "Git")
            'env_paths' = @((Join-Path $env:ProgramFiles "Git\cmd"), (Join-Path $env:ProgramFiles "Git\bin"))
        }
        'putty'= @{
            'url'= "http://dcos-win.westus.cloudapp.azure.com/downloads//putty-64bit-0.70-installer.msi"
            'install_args'= @("/q")
            'install_dir'= (Join-Path $env:ProgramFiles "PuTTY")
            'env_paths' = @((Join-Path $env:ProgramFiles "PuTTY"))
        }
    }
    foreach($program in $prerequisites.Keys) {
        if(Test-Path $prerequisites[$program]['install_dir']) {
            Write-Output "$program is already installed"
            Add-ToSystemPath $prerequisites[$program]['env_paths']
            continue
        }
        Write-Output "Downloading $program from $($prerequisites[$program]['url'])"
        $fileName = $prerequisites[$program]['url'].Split('/')[-1]
        $programFile = Join-Path $env:TEMP $fileName
        Invoke-WebRequest -UseBasicParsing -Uri $prerequisites[$program]['url'] -OutFile $programFile
        $parameters = @{
            'FilePath' = $programFile
            'ArgumentList' = $prerequisites[$program]['install_args']
            'Wait' = $true
            'PassThru' = $true
        }
        if($programFile.EndsWith('.msi')) {
            $parameters['FilePath'] = 'msiexec.exe'
            $parameters['ArgumentList'] += @("/i", $programFile)
        }
        Write-Output "Installing $programFile"
        $p = Start-Process @parameters
        if($p.ExitCode -ne 0) {
            Throw "Failed to install prerequisite $programFile during the environment setup"
        }
        Add-ToSystemPath $prerequisites[$program]['env_paths']
    }
}

function Start-JenkinsCIScriptsGitClone {
    if(Test-Path $MESOS_JENKINS_DIR) {
        Remove-Item -Recurse -Force -Path $MESOS_JENKINS_DIR
    }
    $p = Start-Process -FilePath 'git.exe' -Wait -PassThru -NoNewWindow -ArgumentList @('clone', $MESOS_JENKINS_URL, $MESOS_JENKINS_DIR)
    if($p.ExitCode -ne 0) {
        Throw "Failed to clone $MESOS_JENKINS_URL repository"
    }
}

function Start-MesosAgentSetup {
    [string[]]$masterAddress = ConvertFrom-Json $MasterIP # We might have a JSON encoded list of master IPs
    & "$MESOS_JENKINS_DIR\DCOS\mesos-agent-setup.ps1" -MasterAddress $masterAddress -MesosWindowsBinariesURL $MESOS_BINARIES_URL `
                                                      -AgentPrivateIP $AgentPrivateIP -Public:$isPublic -CustomAttributes $customAttrs
    if($LASTEXITCODE) {
        Throw "Failed to setup the Mesos Windows agent"
    }
}


try {
    Install-Prerequisites
    Start-JenkinsCIScriptsGitClone
    Start-MesosAgentSetup
} catch {
    Write-Output $_.ToString()
    exit 1
}
