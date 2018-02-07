New-Item -ItemType Directory -Force -Path C:/DCOS/mesos/service/

$UTF8NoBOM = New-Object System.Text.UTF8Encoding $False

$cred = "{`"principal`": `"mycred1`", `"secret`": `"mysecret1`"}"
[System.IO.File]::WriteAllLines("C:\DCOS\mesos\service\credential.json", $cred, $UTF8NoBOM)

$httpCred = "{`"credentials`": [{`"principal`": `"mycred2`", `"secret`": `"mysecret2`"}]}"
[System.IO.File]::WriteAllLines("C:\DCOS\mesos\service\http_credential.json", $httpCred, $UTF8NoBOM)

$serviceEnv = "MESOS_AUTHENTICATE_HTTP_READONLY=true`r`nMESOS_AUTHENTICATE_HTTP_READWRITE=true`r`nMESOS_HTTP_CREDENTIALS=C:\DCOS\mesos\service\http_credential.json`r`nMESOS_CREDENTIAL=C:\DCOS\mesos\service\credential.json"
[System.IO.File]::WriteAllLines("C:\DCOS\mesos\service\environment-file", $serviceEnv, $UTF8NoBOM)
