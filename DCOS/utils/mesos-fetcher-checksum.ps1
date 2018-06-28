$ErrorActionPreference = "Stop"

$DOCKER_CONTAINER_ID = docker.exe ps | Where-Object { $_.Contains("->80/tcp") } | ForEach-Object { $_.Split()[0] }
if($LASTEXITCODE) {
    Throw "Fail to run: docker ps"
}
if(!$DOCKER_CONTAINER_ID) {
    Throw "There isn't any container with port 80 exposed"
}
docker exec -u Administrator $DOCKER_CONTAINER_ID cmd /S /C copy C:\mesos\sandbox\fetcher-test.zip C:\fetcher-test.zip 2>&1 | Out-Null
if($LASTEXITCODE) {
    Throw "Fail to copy fetcher file to C:\"
}
$localFile = Join-Path $env:TEMP "fetcher-test.zip"
if(Test-Path $localFile) {
    Remove-Item -Recurse -Force -Path $localFile
}
docker cp "${DOCKER_CONTAINER_ID}:/fetcher-test.zip" $localFile
if($LASTEXITCODE) {
    Throw "Fail to execute: docker cp"
}
(Get-FileHash -Algorithm MD5 -Path $localFile).Hash
Remove-Item -Force -Path $localFile -ErrorAction SilentlyContinue
