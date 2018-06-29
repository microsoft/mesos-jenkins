$ErrorActionPreference = "Stop"

$BASE_URL = "http://dcos-win.westus.cloudapp.azure.com/dcos-windows/testing/preprovision/extensions/preprovision-agent-windows/v1"
$SCRIPTS_DIRECTORY = Join-Path $env:TEMP "preprovision_scripts"
$CI_SETUP_SCRIPT = "preprovision-agent-windows-ci-setup.ps1"
$AGENT_CREDS_SCRIPT = "preprovision-agent-windows-mesos-credentials.ps1"
$FLUENTD_SCRIPT = "preprovision-agent-windows-fluentd.ps1"
$SCRIPTS = @{
    "ci_setup" = @{
        "url" = "$BASE_URL/$CI_SETUP_SCRIPT"
        "local_file" = Join-Path $SCRIPTS_DIRECTORY $CI_SETUP_SCRIPT
    }
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
    Write-Output "Downloading: $($SCRIPTS[$script]["url"])"
    curl.exe -s --retry 10 $SCRIPTS[$script]["url"] -o $SCRIPTS[$script]["local_file"]
    if($LASTEXITCODE) {
        Write-Output "Failed to download $($SCRIPTS[$script]["url"])"
        exit 1
    }
    Write-Output "Executing script with full path $($SCRIPTS[$script]["local_file"])"
    & $SCRIPTS[$script]["local_file"]
    if ($LASTEXITCODE) {
        Write-Output "The script $($SCRIPTS[$script]["local_file"]) didn't finish succesfully"
        exit 1
    }
}
Write-Output "Finished preprovisioning mesos credentials and fluentd agent"
