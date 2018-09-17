$ErrorActionPreference = "Stop"

$DCOS_DIR = Join-Path $env:SystemDrive "opt\mesosphere"

& "$DCOS_DIR\bin\systemctl.exe" stop "dcos-metrics-agent.service"
if($LASTEXITCODE) {
    Throw "Failed to stop dcos-metrics-agent.service"
}

& "$DCOS_DIR\bin\systemctl.exe" disable "dcos-metrics-agent.service"
if($LASTEXITCODE) {
    Throw "Failed to disable dcos-metrics-agent.service"
}

$serviceListFile = Join-Path $DCOS_DIR "bin\servicelist.txt"
$newContent = Get-Content $serviceListFile | Where-Object { $_ -notmatch 'dcos-metrics-agent.service' }
Set-Content -Path $serviceListFile -Value $newContent -Encoding ascii

& "$DCOS_DIR\bin\systemctl.exe" stop "dcos-diagnostics.service"
if($LASTEXITCODE) {
    Throw "Failed to restart dcos-diagnostics.service"
}

& "$DCOS_DIR\bin\systemctl.exe" start "dcos-diagnostics.service"
if($LASTEXITCODE) {
    Throw "Failed to restart dcos-diagnostics.service"
}
