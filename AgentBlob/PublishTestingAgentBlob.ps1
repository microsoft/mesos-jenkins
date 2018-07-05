Param(
    [Parameter(Mandatory=$true)]
    [string]$ArtifactsDirectory,
    [string]$ReleaseVersion=$(Get-Date -Format "MM-dd-yyy_HH-mm-ss"),
    [string]$ParametersFile="${env:TEMP}\publish-blob-parameters.json",
    [switch]$NewLatestSymlink
)

$ErrorActionPreference = "Stop"

$globalVariables = (Resolve-Path "$PSScriptRoot\..\global-variables.ps1").Path
. $globalVariables
$ciUtils = (Resolve-Path "$PSScriptRoot\..\Modules\CIUtils").Path
Import-Module $ciUtils

$global:PARAMETERS = @{
    "BUILD_STATUS" = $null
    "DCOS_WINDOWS_BOOTSTRAP_URL" = "${STORAGE_SERVER_BASE_URL}/dcos-windows/testing/windows-agent-blob/${ReleaseVersion}"
}
$REMOTE_BASE_DIR = "/data/dcos-windows/testing/windows-agent-blob"


function Copy-FilesToRemoteServer {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$LocalFilesPath,
        [Parameter(Mandatory=$true)]
        [string]$RemoteFilesPath
    )
    Write-Output "Started copying files from $LocalFilesPath to remote location at ${server}:${RemoteFilesPath}"
    Start-SCPCommand -Server $STORAGE_SERVER_ADDRESS -User $STORAGE_SERVER_USER -Key $env:SSH_KEY `
                     -LocalPath $LocalFilesPath -RemotePath $RemoteFilesPath
}

function New-RemoteDirectory {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$RemoteDirectoryPath
    )
    $remoteCMD = "if [[ -d $RemoteDirectoryPath ]]; then rm -rf $RemoteDirectoryPath; fi; mkdir -p $RemoteDirectoryPath"
    Start-SSHCommand -Server $STORAGE_SERVER_ADDRESS -User $STORAGE_SERVER_USER -Key $env:SSH_KEY -Command $remoteCMD
}

function New-RemoteSymlink {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$RemotePath,
        [Parameter(Mandatory=$false)]
        [string]$RemoteSymlinkPath
    )
    $remoteCMD = "if [[ -h $RemoteSymlinkPath ]]; then unlink $RemoteSymlinkPath; fi; ln -s $RemotePath $RemoteSymlinkPath"
    Start-SSHCommand -Server $STORAGE_SERVER_ADDRESS -User $STORAGE_SERVER_USER -Key $env:SSH_KEY -Command $remoteCMD
}

function Publish-BuildArtifacts {
    if(!(Test-Path $ArtifactsDirectory)) {
        Throw "The artifacts directory doesn't exist"
    }
    if((Get-ChildItem $ArtifactsDirectory).Count -eq 0) {
        Throw "The artifacts directory is empty"
    }
    $remoteBuildDir = "${REMOTE_BASE_DIR}/${ReleaseVersion}"
    New-RemoteDirectory -RemoteDirectoryPath $remoteBuildDir
    Copy-FilesToRemoteServer "${ArtifactsDirectory}\*" $remoteBuildDir
    Write-Output "Testing agent blob published to: $($global:PARAMETERS['DCOS_WINDOWS_BOOTSTRAP_URL'])"
    if($NewLatestSymlink) {
        New-RemoteSymlink -RemotePath $remoteBuildDir -RemoteSymlinkPath "${REMOTE_BASE_DIR}/latest"
    }
}

function New-ParametersFile {
    if(Test-Path $ParametersFile) {
        Remove-Item -Force $ParametersFile
    }
    New-Item -ItemType File -Path $ParametersFile | Out-Null
}

function Write-ParametersFile {
    $json = ConvertTo-Json -InputObject $global:PARAMETERS
    Set-Content -Path $ParametersFile -Value $json -Encoding Ascii
}


try {
    New-ParametersFile
    Publish-BuildArtifacts
    $global:PARAMETERS["BUILD_STATUS"] = "PASS"
} catch {
    Write-Output $_.ToString()
    Write-Output $_.ScriptStackTrace
    $global:PARAMETERS["BUILD_STATUS"] = "FAIL"
    exit 1
} finally {
    Write-ParametersFile
}
exit 0
