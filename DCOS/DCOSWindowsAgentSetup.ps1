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

$SCRIPTS_REPO_URL = "https://github.com/ionutbalutoiu/mesos-jenkins" # TODO: Change this to the official repo URL
$SCRIPTS_DIR = Join-Path $env:TEMP "mesos-jenkins"
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

function New-ScriptsDirectory {
    if(Test-Path $SCRIPTS_DIR) {
        Remove-Item -Recurse -Force -Path $SCRIPTS_DIR
    }
    $p = Start-Process -FilePath 'git.exe' -Wait -PassThru -NoNewWindow -ArgumentList @('clone', $SCRIPTS_REPO_URL, $SCRIPTS_DIR)
    if($p.ExitCode -ne 0) {
        Throw "Failed to clone $SCRIPTS_REPO_URL repository"
    }
}

function Get-MasterIPs {
    [string[]]$ips = ConvertFrom-Json $MasterIP
    # NOTE(ibalutoiu): ACS-Engine adds the Zookeper port to every master IP and we need only the address
    [string[]]$masterIPs = $ips | ForEach-Object { $_.Split(':')[0] }
    return $masterIPs
}

function Install-MesosAgent {
    $masterIPs = Get-MasterIPs
    & "$SCRIPTS_DIR\DCOS\mesos-agent-setup.ps1" -MasterAddress $masterIPs -MesosWindowsBinariesURL $MESOS_BINARIES_URL `
                                                -AgentPrivateIP $AgentPrivateIP -Public:$isPublic -CustomAttributes $customAttrs
    if($LASTEXITCODE) {
        Throw "Failed to setup the DCOS Mesos Windows slave agent"
    }
}

function Install-ErlangRuntime {
    & "$SCRIPTS_DIR\DCOS\erlang-setup.ps1"
    if($LASTEXITCODE) {
        Throw "Failed to setup the Windows Erlang runtime"
    }
}

function Install-EPMDAgent {
    & "$SCRIPTS_DIR\DCOS\epmd-agent-setup.ps1"
    if($LASTEXITCODE) {
        Throw "Failed to setup the DCOS EPMD Windows agent"
    }
}

function Install-SpartanAgent {
    $masterIPs = Get-MasterIPs
    & "$SCRIPTS_DIR\DCOS\spartan-agent-setup.ps1" -MasterAddress $masterIPs -AgentPrivateIP $AgentPrivateIP -Public:$isPublic
    if($LASTEXITCODE) {
        Throw "Failed to setup the DCOS Spartan Windows agent"
    }
}


try {
    Install-Prerequisites
    New-ScriptsDirectory
    Install-MesosAgent
    Install-ErlangRuntime
    Install-EPMDAgent
    Install-SpartanAgent
    Set-NetFirewallRule -Name 'FPS-SMB-In-TCP' -Enabled True # The SMB firewall rule is needed when collecting logs
} catch {
    Write-Output $_.ToString()
    exit 1
}
Write-Output "Successfully finished setting up the DCOS Windows Agent"
exit 0
