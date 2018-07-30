$ErrorActionPreference = "Stop"

if (!${env:DOCKER_HUB_USER}) {
    Write-Output "Docker user is not set."
    exit 1
}

if (!${env:DOCKER_HUB_USER_PASSWORD}) {
    Write-Output "Docker user password is not set."
    exit 1
}

$globalVariables = (Resolve-Path "$PSScriptRoot\..\global-variables.ps1").Path
$ciUtils = (Resolve-Path "$PSScriptRoot\..\Modules\CIUtils").Path

Import-Module $ciUtils
. $globalVariables

$DOCKERFILE_PATH = Join-Path $PSScriptRoot "ci-image-Dockerfile"
$IMAGE_FILES_DIR = Join-Path $env:WORKSPACE "files"
$IMAGE_FILES_BASE_URL = "${STORAGE_SERVER_BASE_URL}/downloads"

# Do a login into docker
Write-Output ${env:DOCKER_HUB_USER_PASSWORD} | docker login -u ${env:DOCKER_HUB_USER} --password-stdin
if ($LASTEXITCODE) {
    Write-Output "ERROR: Failed to login to docker using provided credentials."
    exit 1
}

# Check if docker images exist and delete them
$listWinImage = Start-ExternalCommand -ScriptBlock { docker image list ${env:DOCKER_HUB_USER}/windows -q -a } `
                                       -ErrorMessage "Failed to run docker image list for ${env:DOCKER_HUB_USER}/windows"
if ($listWinImage) {
    Write-Output "WARNING: Docker image for ${env:DOCKER_HUB_USER}/windows:1803 already exists. Removing"
    Start-ExternalCommand -ScriptBlock { docker rmi -f $(docker image list ${env:DOCKER_HUB_USER}/windows -q -a) } `
                          -ErrorMessage "ERROR: Failed to remove image ${env:DOCKER_HUB_USER}/windows"
}

$listMSImage = Start-ExternalCommand -ScriptBlock { docker image list microsoft/nanoserver -q -a } `
                                      -ErrorMessage "Failed to run docker image list for microsoft/nanoserver"
if ($listMSImage) {
    Write-Output "WARNING: Docker image for microsoft/nanoserver:1803 already exists. Removing"
    Start-ExternalCommand -ScriptBlock { docker rmi -f $(docker image list microsoft/nanoserver -q -a) } `
                          -ErrorMessage "ERROR: Failed to remove image microsoft/nanoserver"
}

# Download files
Write-Output "Downloading mandatory files for the image"
New-Item -ItemType Directory "$IMAGE_FILES_DIR"

Push-Location "$IMAGE_FILES_DIR"

# Download webserver.exe and MD5.exe
Start-FileDownload -URL "${IMAGE_FILES_BASE_URL}/webserver.exe" -Destination "${IMAGE_FILES_DIR}\webserver.exe"
Start-FileDownload -URL "${IMAGE_FILES_BASE_URL}/MD5.exe" -Destination "${IMAGE_FILES_DIR}\MD5.exe"

# Start Building the nano image using a Dockerfile
Write-Output "Building Windows nano image"
Start-ExternalCommand -ScriptBlock { docker build --no-cache -t "${env:DOCKER_HUB_USER}/windows:1803" -f "$DOCKERFILE_PATH" . } `
                      -ErrorMessage "ERROR: Failed to build Windows nano image from Dockerfile"

# Set tag for the private windows image
Start-ExternalCommand -ScriptBlock { docker tag ${env:DOCKER_HUB_USER}/windows:1803 ${env:DOCKER_HUB_USER}/private-windows:1803 } `
                      -ErrorMessage "ERROR: Failed to set tag for Windows nano private image"

# Push the new images into Docker Hub
Write-Output "Starting pushing created images to Docker Hub"
Start-ExternalCommand -ScriptBlock { docker push ${env:DOCKER_HUB_USER}/windows:1803 } `
                      -ErrorMessage "ERROR: Failed to push Windows nano image to Docker Hub"
Start-ExternalCommand -ScriptBlock { docker push ${env:DOCKER_HUB_USER}/private-windows:1803 } `
                      -ErrorMessage "ERROR: Failed to push Windows nano private image to Docker Hub"
Write-Output "The images have been updated"

Pop-Location

# Do some cleanup of the created images
Write-Output "Cleaning up docker images"
Start-ExternalCommand -ScriptBlock { docker rmi -f $(docker images ${env:DOCKER_HUB_USER}/windows -q -a) } `
                      -ErrorMessage "ERROR: Failed to remove image ${env:DOCKER_HUB_USER}/windows"
Start-ExternalCommand -ScriptBlock { docker rmi -f $(docker images microsoft/nanoserver -q -a) } `
                      -ErrorMessage "ERROR: Failed to remove image microsoft/nanoserver"
