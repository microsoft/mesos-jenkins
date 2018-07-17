$ErrorActionPreference = "Stop"

$CONFIG_WINRM_SCRIPT = "https://raw.githubusercontent.com/ansible/ansible/v2.5.0a1/examples/scripts/ConfigureRemotingForAnsible.ps1"


filter Timestamp { "[$(Get-Date -Format o)] $_" }

function Write-Log {
    Param(
        [string]$Message
    )
    $msg = $message | Timestamp
    Write-Output $msg
}

function Start-FileDownloadWithCurl {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$URL,
        [Parameter(Mandatory=$true)]
        [string]$Destination,
        [Parameter(Mandatory=$false)]
        [int]$RetryCount=10
    )
    curl.exe --retry $RetryCount -o `"$Destination`" `"$URL`"
    if($LASTEXITCODE) {
        Throw "Fail to download $URL"
    }
}

function Start-ExecuteWithRetry {
    Param(
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$ScriptBlock,
        [int]$MaxRetryCount=10,
        [int]$RetryInterval=3,
        [string]$RetryMessage,
        [array]$ArgumentList=@()
    )
    $currentErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $retryCount = 0
    while ($true) {
        Write-Log "Start-ExecuteWithRetry attempt $retryCount"
        try {
            $res = Invoke-Command -ScriptBlock $ScriptBlock `
                                  -ArgumentList $ArgumentList
            $ErrorActionPreference = $currentErrorActionPreference
            Write-Log "Start-ExecuteWithRetry terminated"
            return $res
        } catch [System.Exception] {
            $retryCount++
            if ($retryCount -gt $MaxRetryCount) {
                $ErrorActionPreference = $currentErrorActionPreference
                Write-Log "Start-ExecuteWithRetry exception thrown"
                throw
            } else {
                if($RetryMessage) {
                    Write-Log "Start-ExecuteWithRetry RetryMessage: $RetryMessage"
                } elseif($_) {
                    Write-Log "Start-ExecuteWithRetry Retry: $_.ToString()"
                }
                Start-Sleep $RetryInterval
            }
        }
    }
}

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

function Install-Git {
    Write-Log "Enter Install-Git"
    $gitInstallerURL = "http://dcos-win.westus.cloudapp.azure.com/downloads/git-64-bit.exe"
    $gitInstallDir = Join-Path $env:ProgramFiles "Git"
    $gitPaths = @("$gitInstallDir\cmd", "$gitInstallDir\bin")
    if(Test-Path $gitInstallDir) {
        Write-Log "Git is already installed"
        Add-ToSystemPath $gitPaths
        Write-Log "Exit Install-Git: already installed"
        return
    }
    Write-Log "Downloading Git from $gitInstallerURL"
    $programFile = Join-Path $env:TEMP "git.exe"
    Start-FileDownloadWithCurl -URL $gitInstallerURL -Destination $programFile
    $parameters = @{
        'FilePath' = $programFile
        'ArgumentList' = @("/SILENT")
        'Wait' = $true
        'PassThru' = $true
    }
    Write-Log "Installing Git"
    $p = Start-Process @parameters
    if($p.ExitCode -ne 0) {
        Throw "Failed to install Git during the environment setup"
    }
    Add-ToSystemPath $gitPaths
    Write-Log "Exit Install-Git"
}

try {
    #
    # Install Git
    #
    Install-Git

    #
    # Enable the SMB firewall rule needed when collecting logs
    #
    Set-NetFirewallRule -Name 'FPS-SMB-In-TCP' -Enabled True

    #
    # Configure WinRM
    #
    $configWinRMScript = Join-Path $env:SystemDrive "AzureData\ConfigureWinRM.ps1"
    Start-FileDownloadWithCurl -URL $CONFIG_WINRM_SCRIPT -Destination $configWinRMScript -RetryCount 30
    & $configWinRMScript
    if($LASTEXITCODE -ne 0) {
        Throw "Failed to configure WinRM"
    }

    #
    # Remove all the cached Docker images
    #
    docker.exe image rm $(docker.exe image ls -q)
    if($LASTEXITCODE) {
        Throw "Failed to remove cached Docker images"
    }

    #
    # Pre-pull CI images
    #
    $images = @(
        "microsoft/windowsservercore:1803",
        "microsoft/nanoserver:1803",
        "microsoft/iis:windowsservercore-1803",
        "dcoswindowsci/windows:1803"
    )
    foreach($img in $images) {
        Start-ExecuteWithRetry -ScriptBlock { docker.exe pull $img } `
                               -MaxRetryCount 30 -RetryInterval 3 `
                               -RetryMessage "Failed to pre-pull $img Docker image. Retrying"
    }

    #
    # Enable Docker debug logging and capture stdout and stderr to a file.
    # We're using the updated service wrapper for this.
    #
    $serviceName = "Docker"
    $dockerHome = Join-Path $env:ProgramFiles "Docker"
    $wrapperUrl = "http://dcos-win.westus.cloudapp.azure.com/downloads/service-wrapper.exe"
    Stop-Service $serviceName
    sc.exe delete $serviceName
    if($LASTEXITCODE) {
        Throw "Failed to delete service: $serviceName"
    }
    Start-FileDownloadWithCurl -URL $wrapperUrl -Destination "${dockerHome}\service-wrapper.exe" -RetryCount 30
    $binPath = ("`"${dockerHome}\service-wrapper.exe`" " +
                "--service-name `"$serviceName`" " +
                "--exec-start-pre `"powershell.exe if(Test-Path '${env:ProgramData}\docker\docker.pid') { Remove-Item -Force '${env:ProgramData}\docker\docker.pid' }`" " +
                "--log-file `"$dockerHome\dockerd.log`" " +
                "`"$dockerHome\dockerd.exe`" -D")
    New-Service -Name $serviceName -StartupType "Automatic" -Confirm:$false `
                -DisplayName "Docker Windows Agent" -BinaryPathName $binPath
    sc.exe failure $serviceName reset=5 actions=restart/1000
    if($LASTEXITCODE) {
        Throw "Failed to set $serviceName service recovery options"
    }
    sc.exe failureflag $serviceName 1
    if($LASTEXITCODE) {
        Throw "Failed to set $serviceName service recovery options"
    }
    Start-Service $serviceName
} catch {
    Write-Log "preprovision-agent-windows-ci-setup.ps1 exception: $_.ToString()"
    Write-Log $_.ScriptStackTrace
    Write-Log "The CI setup for the DC/OS node failed"
    exit 1
}
Write-Log "preprovision-agent-windows-ci-setup.ps1 completed"
exit 0
