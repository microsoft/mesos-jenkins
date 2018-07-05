$ErrorActionPreference = "Stop"

$DOCKER_CONTAINER_ID = docker.exe ps | Where-Object { $_.Contains("->80/tcp") } | ForEach-Object { $_.Split()[0] }
if($LASTEXITCODE) {
    Throw "Fail to run: docker ps"
}
if(!$DOCKER_CONTAINER_ID) {
    Throw "There isn't any container with port 80 exposed"
}
docker exec -u Administrator $DOCKER_CONTAINER_ID cmd /S /C MD5.exe C:\mesos\sandbox\fetcher-test.zip
if($LASTEXITCODE) {
    Throw "Fail to get the MD5 checksum for the fetcher file"
}
