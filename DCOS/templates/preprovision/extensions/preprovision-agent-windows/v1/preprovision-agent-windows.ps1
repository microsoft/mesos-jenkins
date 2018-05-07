$ErrorActionPreference = "Stop"

$BASE_URL = "http://dcos-win.westus.cloudapp.azure.com/dcos-windows/testing/preprovision/extensions/preprovision-agent-windows/v1"
$SCRIPTS_DIRECTORY = Join-Path $env:TEMP "preprovision_scripts"
$AGENT_CREDS_SCRIPT="preprovision-agent-windows-credentials.ps1"
$FLUENTD_SCRIPT="preprovision-agent-windows-fluentd.ps1"
$SCRIPTS = @{
    "agent_creds" = @{
        "url" = "$BASE_URL/$AGENT_CREDS_SCRIPT"
        "local_file" = Join-Path $SCRIPTS_DIRECTORY $AGENT_CREDS_SCRIPT
    }
	"fluentd" = @{
        "url" = "$BASE_URL/$FLUENTD_SCRIPT"
        "local_file" = Join-Path $SCRIPTS_DIRECTORY $FLUENTD_SCRIPT
    }
}

if(!(Test-Path $SCRIPTS_DIRECTORY)) {
        New-Item -ItemType "Directory" -Path $SCRIPTS_DIRECTORY
}

foreach($script in $SCRIPTS.Keys) {
	Write-Host "Downloading: $($SCRIPTS[$script]["url"])"
	Start-BitsTransfer $SCRIPTS[$script]["url"] -Destination $SCRIPTS[$script]["local_file"]
	Write-Host "Executing script with full path $($SCRIPTS[$script]["local_file"])"
	& $SCRIPTS[$script]["local_file"]
}
Write-Host "Finished preprovisioning credentials and fluentd agent"
