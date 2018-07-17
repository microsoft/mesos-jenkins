$ErrorActionPreference = "Stop"

$MESOS_SERVICE_DIR = Join-Path $env:SystemDrive "DCOS\mesos\service"
$MESOS_SERVICE_NAME = "dcos-mesos-slave" # TODO(ibalutoiu): To be removed once custom data execute after pre-provision scripts

New-Item -ItemType Directory -Force -Path $MESOS_SERVICE_DIR

$UTF8NoBOM = New-Object System.Text.UTF8Encoding $False

$cred = "{`"principal`": `"mycred1`", `"secret`": `"mysecret1`"}"
[System.IO.File]::WriteAllLines("$MESOS_SERVICE_DIR\credential.json", $cred, $UTF8NoBOM)

$httpCred = "{`"credentials`": [{`"principal`": `"mycred2`", `"secret`": `"mysecret2`"}]}"
[System.IO.File]::WriteAllLines("$MESOS_SERVICE_DIR\http_credential.json", $httpCred, $UTF8NoBOM)

$serviceEnv = "MESOS_AUTHENTICATE_HTTP_READONLY=true`r`nMESOS_AUTHENTICATE_HTTP_READWRITE=true`r`nMESOS_HTTP_CREDENTIALS=$MESOS_SERVICE_DIR\http_credential.json`r`nMESOS_CREDENTIAL=$MESOS_SERVICE_DIR\credential.json"
[System.IO.File]::WriteAllLines("$MESOS_SERVICE_DIR\environment-file", $serviceEnv, $UTF8NoBOM)

#
# TODO(ibalutoiu): Remove this once we have pre-provision scripts executed
#                  before custom data.
#
$service = Get-Service -Name $MESOS_SERVICE_NAME -ErrorAction SilentlyContinue
if($service) {
    Restart-Service -Name $MESOS_SERVICE_NAME -Force -Confirm:$false
}
