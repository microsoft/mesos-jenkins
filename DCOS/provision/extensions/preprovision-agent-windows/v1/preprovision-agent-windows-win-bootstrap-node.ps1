$ErrorActionPreference = "Stop"

$CONFIG_WINRM_SCRIPT = "https://raw.githubusercontent.com/ansible/ansible/v2.5.0a1/examples/scripts/ConfigureRemotingForAnsible.ps1"
$FLUENTD_TD_AGENT_URL = "http://packages.treasuredata.com.s3.amazonaws.com/3/windows/td-agent-3.1.1-0-x64.msi"
$MESOS_CREDENTIALS_DIR = Join-Path $env:SystemDrive "AzureData\mesos"


filter Timestamp { "[$(Get-Date -Format o)] $_" }

function Write-Log {
    Param(
        [string]$Message
    )
    $msg = $message | Timestamp
    Write-Output $msg
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

function Start-FileDownloadWithCurl {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$URL,
        [Parameter(Mandatory=$true)]
        [string]$Destination,
        [Parameter(Mandatory=$false)]
        [int]$RetryCount=10
    )
    $params = @('-fLsS', '-o', "`"${Destination}`"", "`"${URL}`"")
    Start-ExecuteWithRetry -ScriptBlock {
        $p = Start-Process -FilePath 'curl.exe' -NoNewWindow -ArgumentList $params -Wait -PassThru
        if($p.ExitCode -ne 0) {
            Throw "Fail to download $URL"
        }
    } -MaxRetryCount $RetryCount -RetryInterval 3 -RetryMessage "Failed to download ${URL}. Retrying"
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
    $gitInstallerURL = "http://dcos-win.westus2.cloudapp.azure.com/downloads/git-64-bit.exe"
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

function Start-CIAgentSetup {
    Install-Git
    # Enable the SMB firewall rule needed when collecting logs
    Set-NetFirewallRule -Name 'FPS-SMB-In-TCP' -Enabled True
    # Configure WinRM
    $configWinRMScript = Join-Path $env:SystemDrive "AzureData\ConfigureWinRM.ps1"
    Start-FileDownloadWithCurl -URL $CONFIG_WINRM_SCRIPT -Destination $configWinRMScript -RetryCount 30
    & $configWinRMScript
    if($LASTEXITCODE -ne 0) {
        Throw "Failed to configure WinRM"
    }
    # Pre-pull CI images
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
    # Enable Docker debug logging and capture stdout and stderr to a file.
    # We're using the updated service wrapper for this.
    $serviceName = "Docker"
    $dockerHome = Join-Path $env:ProgramFiles "Docker"
    $wrapperUrl = "http://dcos-win.westus2.cloudapp.azure.com/downloads/service-wrapper.exe"
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
}

function Install-FluentdAgent () {
    Write-Output "Downloading fluentd/td-agent..."
    $fileName = $FLUENTD_TD_AGENT_URL.Split('/')[-1]
    $installerPath = Join-Path $env:TEMP $fileName
    Start-FileDownloadWithCurl -URL $FLUENTD_TD_AGENT_URL -Destination $installerPath

    Write-Output "Installing fluentd..."
    $dataStamp = Get-Date -Format "yyyyMMddTHHmmss"
    [String]$logFile = "{0}-{1}.log" -f @($installerPath, $dataStamp)
    $msiArguments = @(
        "/i"                         # Install
        ('"{0}"' -f $installerPath)  # MSI path
        "/qn"                        # No UI
        "/norestart"                 # No computer restart
        "/L*v"                       # Log everything including verbose
        $logFile                     # Log file name
    )
    $process = Start-Process "msiexec.exe" -ArgumentList $msiArguments -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0) {
        Throw "ERROR: Failed to install Fluentd. Error code: " + $process.ExitCode + " See details in log: $logFile"
    }
    $fluentBin = Join-Path $env:SystemDrive "opt\td-agent\embedded\bin"
    $env:Path = "${fluentBin};" + $env:Path
}

function Register-FluentdService () {
    Write-Output "Registering fluentd service..."
    fluentd --reg-winsvc i
    if ($LASTEXITCODE) {
        Throw "Failed to register fluentd Windows service. ExitCode = $LASTEXITCODE"
    }
    $configFile = Join-Path $env:SystemDrive "opt/td-agent/etc/td-agent/td-agent.conf"
    $logFile = Join-Path $env:SystemDrive "opt/td-agent/td-agent.log"
    Set-Content -Path $configFile -Encoding Ascii -Value @"
<source>
  @type forward
</source>
<source>
  @type tail
  path C:/AzureData/fluentd-testing/stdout
  tag log.stdout
  refresh_interval 5s
  format none
  read_from_head true
  pos_file C:/AzureData/fluentd-testing/stdout.pos
</source>
<match log.*>
  @type file
  path C:/AzureData/fluentd-testing/logs
  <buffer>
    @type file
    flush_mode immediate
  </buffer>
</match>
"@
    fluentd --reg-winsvc-fluentdopt "-c $configFile -o $logFile"
    if ($LASTEXITCODE) {
        Throw "Failed to set options for fluentd Windows service. ExitCode = $LASTEXITCODE"
    }
    Write-Output "Starting fluentd service..."
    Start-Service "fluentdwinsvc"
}

function Start-FluentdSetup {
    $fluentdTestingDir = Join-Path $env:SystemDrive "AzureData\fluentd-testing"
    if(Test-Path $fluentdTestingDir) {
        Remove-Item -Recurse -Force -Path $fluentdTestingDir
    }
    New-Item -ItemType "Directory" -Path $fluentdTestingDir
    Install-FluentdAgent
    Register-FluentdService
}

function Write-MesosSecretFiles {
    # Write the credential files
    # NOTE: These are only some dumb secrets used for testing. DO NOT use in production!
    if(Test-Path $MESOS_CREDENTIALS_DIR) {
        Remove-Item -Recurse -Force $MESOS_CREDENTIALS_DIR
    }
    New-Item -ItemType "Directory" -Path $MESOS_CREDENTIALS_DIR -Force
    $utf8NoBOM = New-Object System.Text.UTF8Encoding $false
    $credentials = @{
        "principal" = "mycred1"
        "secret" = "mysecret1"
    }
    $json = ConvertTo-Json -InputObject $credentials -Compress
    [System.IO.File]::WriteAllLines("$MESOS_CREDENTIALS_DIR\credential.json", $json, $utf8NoBOM)
    $httpCredentials = @{
        "credentials" = @(
            @{
                "principal" = "mycred2"
                "secret" = "mysecret2"
            }
        )
    }
    $json = ConvertTo-Json -InputObject $httpCredentials -Compress
    [System.IO.File]::WriteAllLines("$MESOS_CREDENTIALS_DIR\http_credential.json", $json, $utf8NoBOM)
    # Create the Mesos service environment file with authentication enabled
    $serviceEnv = @(
        "`$env:MESOS_AUTHENTICATE_HTTP_READONLY='true'",
        "`$env:MESOS_AUTHENTICATE_HTTP_READWRITE='true'",
        "`$env:MESOS_HTTP_CREDENTIALS=`"$MESOS_CREDENTIALS_DIR\http_credential.json`"",
        "`$env:MESOS_CREDENTIAL=`"$MESOS_CREDENTIALS_DIR\credential.json`""
    )
    Set-Content -Path "$MESOS_CREDENTIALS_DIR\auth-env.ps1" -Value $serviceEnv -Encoding "default"
}

try {
    Start-CIAgentSetup
    Start-FluentdSetup
    Write-MesosSecretFiles
    Write-Output "Successfully executed the preprovision-agent-windows.ps1 script"
} catch {
    Write-Log "The pre-provision setup for the DC/OS Windows node failed"
    Write-Log "preprovision-agent-windows-setup.ps1 exception: $_.ToString()"
    Write-Log $_.ScriptStackTrace
    exit 1
}