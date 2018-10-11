$ErrorActionPreference = "Stop"

$DCOS_DIR = Join-Path $env:SystemDrive "opt\mesosphere"
$ETC_DIR = Join-Path $env:SystemDrive "etc"


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
        try {
            $res = Invoke-Command -ScriptBlock $ScriptBlock `
                                  -ArgumentList $ArgumentList
            $ErrorActionPreference = $currentErrorActionPreference
            return $res
        } catch [System.Exception] {
            $retryCount++
            if ($retryCount -gt $MaxRetryCount) {
                $ErrorActionPreference = $currentErrorActionPreference
                Throw
            } else {
                if($RetryMessage) {
                    Write-Output $RetryMessage
                } elseif($_) {
                    Write-Output $_.ToString()
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

#
# Enable Docker debug logging and capture stdout and stderr to a file.
# We're using the updated service wrapper for this.
#
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

#
# Disable dcos-metrics agent
#
Stop-Service -Force "dcos-metrics-agent.service"
sc.exe delete "dcos-metrics-agent.service"
if($LASTEXITCODE) {
    Throw "Failed to delete dcos-metrics-agent.service"
}
Remove-Item -Force "$ETC_DIR\systemd\active\dcos-metrics-agent.service"
Remove-Item -Force "$ETC_DIR\systemd\active\dcos.target.wants\dcos-metrics-agent.service"
Remove-Item -Force "$ETC_DIR\systemd\system\dcos-metrics-agent.service"
Remove-Item -Force "$ETC_DIR\systemd\system\dcos.target.wants\dcos-metrics-agent.service"

#
# Remove dcos-metrics from the list of monitored services for dcos-diagnostics
#
$serviceListFile = Join-Path $DCOS_DIR "bin\servicelist.txt"
$newContent = Get-Content $serviceListFile | Where-Object { $_ -notmatch 'dcos-metrics-agent.service' }
Set-Content -Path $serviceListFile -Value $newContent -Encoding ascii
Restart-Service -Force "dcos-diagnostics.service"
