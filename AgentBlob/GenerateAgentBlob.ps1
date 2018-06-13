Param(
    [string]$DiagnosticsPackageUrl="http://dcos-win.westus.cloudapp.azure.com/diagnostics-build/dcos/latest/binaries/diagnostics.zip",
    [string]$MetricsPackageUrl="http://dcos-win.westus.cloudapp.azure.com/metrics-build/dcos/latest/binaries/metrics.zip",
    [string]$MesosPackageUrl="http://dcos-win.westus.cloudapp.azure.com/mesos-build/apache/latest/binaries/mesos-binaries.zip",
    [string]$DcosNetPackageUrl="http://dcos-win.westus.cloudapp.azure.com/net-build/dcos/latest/release.zip",
    [string]$SpartanPackageUrl="http://dcos-win.westus.cloudapp.azure.com/spartan-build/master/latest/release.zip",
    [string]$DockerBinariesBaseUrl="http://dcos-win.westus.cloudapp.azure.com/downloads/docker/18.03.1-ce"
)

$ErrorActionPreference = "Stop"

# This is a script to package all the DC/OS Windows agent components into single zip 
# file, called WindowsAgentBlob, for speeding up the Windows agent's setup.
# 7-Zip package was added for faster unzipping purpose

$globalVariables = (Resolve-Path "$PSScriptRoot\..\global-variables.ps1").Path
. $globalVariables
$ciUtils = (Resolve-Path "$PSScriptRoot\..\Modules\CIUtils").Path
Import-Module $ciUtils

$SOURCE_FILES = @{
    "MicrosoftWDKInstallers.cab"  = "https://download.microsoft.com/download/7/D/D/7DD48DE6-8BDA-47C0-854A-539A800FAA90/wdk/Installers/787bee96dbd26371076b37b13c405890.cab"
    "httpd-2.4.33-win64-VC15.zip" = "http://dcos-win.westus.cloudapp.azure.com/downloads/httpd-2.4.33-win64-VC15.zip"
    "VC_redist_2013_x64.exe"      = "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe"
    "VC_redist_2017_x64.exe"      = "https://download.visualstudio.microsoft.com/download/pr/11687625/2cd2dba5748dc95950a5c42c2d2d78e4/VC_redist.x64.exe"
    "docker.exe"                  = "${DockerBinariesBaseUrl}/docker.exe"
    "dockerd.exe"                 = "${DockerBinariesBaseUrl}/dockerd.exe"
    "service-wrapper.exe"         = "http://dcos-win.westus.cloudapp.azure.com/downloads/service-wrapper.exe"
    "mesos.zip"                   = $MesosPackageUrl
    "dcos-net.zip"                = $DcosNetPackageUrl
    "metrics.zip"                 = $MetricsPackageUrl
    "diagnostics.zip"             = $DiagnosticsPackageUrl
    # The following two files are pretty big and they are only needed for DC/OS 1.10. We can remove it should we decided to drop support for 1.10
    "spartan.zip"                 = $SpartanPackageUrl
    "erlang.zip"                  = "http://dcos-win.westus.cloudapp.azure.com/downloads/erl8.3.zip"
}
$ARTIFACTS_DIR = Join-Path $env:WORKSPACE "artifacts"
$7ZIP_DOWNLOAD_URL = "https://7-zip.org/a/7z1801-x64.msi"
$SETUP_SCRIPTS_REPO_URL = "https://github.com/dcos/dcos-windows"
$WINDOWS_AGENT_BLOB_FILE_NAME = "windowsAgentBlob.zip"
$REMOTE_BASE_DIR = "/data/windows-agent-blob"

filter Timestamp { "[$(Get-Date -Format o)] $_" }

function Write-Log {
    Param(
        [string]$Message
    )
    $msg = $message | Timestamp
    Write-Output $msg
}

function New-ArtifactsDirectory {
    if(Test-Path $ARTIFACTS_DIR) {
        Remove-Item -Recurse -Force $ARTIFACTS_DIR
    }
    New-Item -ItemType "Directory" -Path $ARTIFACTS_DIR | Out-Null
}

function Get-7ZipInstaller {
    Write-Log "Downloading 7-Zip installer"
    $targetFileName = Split-Path -Path $7ZIP_DOWNLOAD_URL -Leaf
    $targetPath = Join-Path $ARTIFACTS_DIR $targetFileName
    curl.exe --keepalive-time 2 -fLsS --retry 10 -Y 100000 -y 60 -L -o $targetPath $7ZIP_DOWNLOAD_URL
    if($LASTEXITCODE) {
        Throw "Failed to download $7ZIP_DOWNLOAD_URL"
    }
    $sha1sum = (Get-FileHash -Algorithm SHA1 -Path $targetPath).Hash.ToLower()
    Set-Content -Path "${targetPath}.sha1sum" -Value $sha1sum -Encoding Ascii
    Write-Log "Finished downloading 7-Zip"
}

function New-DCOSWindowsAgentBlob {
    Write-Log "New-DCOSWindowsAgentBlob"
    # - Create agentBlob directory into $env:WORKSPACE
    $dcosBlob = Join-Path $env:WORKSPACE "dcosBlob"
    $blobDir = Join-Path $dcosBlob "agentblob"
    if(Test-Path $blobDir) {
        Remove-Item -Recurse -Force $blobDir
    }
    New-Item -ItemType "Directory" -Path $blobDir | Out-Null
    # - Download all the packages
    foreach($fileName in $SOURCE_FILES.Keys) {
        $fileUri = $SOURCE_FILES[$fileName]
        $targetPath = Join-Path $blobDir $fileName
        Write-Log "Downloading $fileUri to $targetPath"
        curl.exe --keepalive-time 2 -fLsS --retry 10 -Y 100000 -y 60 -L -o $targetPath $fileUri
        if($LASTEXITCODE) {
            Throw "Failed to download $fileUri"
        }
    }
    # - Extract DevCon package
    $cabPkg = Join-Path $blobDir "MicrosoftWDKInstallers.cab"
    if(!(Test-Path $cabPkg)) {
        Throw "Cannot find DevCon pkg file: $cabPkg"
    }
    $devConFileName = "filbad6e2cce5ebc45a401e19c613d0a28f"
    expand.exe $cabPkg -F:$devConFileName $blobDir
    if($LASTEXITCODE) {
        Throw "Failed to expand DevCon cab file"
    }
    $devConFile = Join-Path $blobDir $devConFileName
    $devConBinary = Join-Path $blobDir "devcon.exe"
    Move-Item $devConFile $devConBinary
    Remove-Item -Force $cabPkg
    # - Clone dcos/dcos-windows repository
    Write-Log "Cloning dcos-windows repository"
    $setupScripts = Join-Path $blobDir "dcos-windows"
    if(Test-Path $setupScripts) {
        Remove-Item -Recurse -Force -Path $setupScripts
    }
    Start-ExecuteWithRetry -ScriptBlock {
        $p = Start-Process -FilePath 'git.exe' -Wait -PassThru -NoNewWindow -ArgumentList @('clone', $SETUP_SCRIPTS_REPO_URL, $setupScripts)
        if($p.ExitCode -ne 0) {
            Throw "Failed to clone $SETUP_SCRIPTS_REPO_URL repository"
        }
    } -RetryMessage "Failed to clone ${SETUP_SCRIPTS_REPO_URL}"
    Write-Log "Creating zip package from $blobDir"
    $blobTargetPath = Join-Path $ARTIFACTS_DIR $WINDOWS_AGENT_BLOB_FILE_NAME
    if(Test-Path $blobTargetPath) {
        Remove-Item -Recurse -Force $blobTargetPath
    }
    Compress-Files -FilesDirectory $dcosBlob -Archive $blobTargetPath
    Remove-Item -Recurse -Force $dcosBlob
    $sha1sum = (Get-FileHash -Algorithm SHA1 -Path $blobTargetPath).Hash.ToLower()
    Set-Content -Path "${blobTargetPath}.sha1sum" -Value $sha1sum -Encoding Ascii
    Write-Log "Finished generating $WINDOWS_AGENT_BLOB_FILE_NAME"
}

function Copy-FilesToRemoteServer {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$LocalFilesPath,
        [Parameter(Mandatory=$true)]
        [string]$RemoteFilesPath
    )
    Write-Output "Started copying files from $LocalFilesPath to remote location at ${server}:${RemoteFilesPath}"
    Start-SCPCommand -Server $REMOTE_LOG_SERVER -User $REMOTE_USER -Key $env:SSH_KEY `
                     -LocalPath $LocalFilesPath -RemotePath $RemoteFilesPath
}

function New-RemoteDirectory {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$RemoteDirectoryPath
    )
    $remoteCMD = "if [[ -d $RemoteDirectoryPath ]]; then rm -rf $RemoteDirectoryPath; fi; mkdir -p $RemoteDirectoryPath"
    Start-SSHCommand -Server $REMOTE_LOG_SERVER -User $REMOTE_USER -Key $env:SSH_KEY -Command $remoteCMD
}

function New-RemoteSymlink {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$RemotePath,
        [Parameter(Mandatory=$false)]
        [string]$RemoteSymlinkPath
    )
    $remoteCMD = "if [[ -h $RemoteSymlinkPath ]]; then unlink $RemoteSymlinkPath; fi; ln -s $RemotePath $RemoteSymlinkPath"
    Start-SSHCommand -Server $REMOTE_LOG_SERVER -User $REMOTE_USER -Key $env:SSH_KEY -Command $remoteCMD
}

function Publish-BuildArtifacts {
    if(!(Test-Path $ARTIFACTS_DIR)) {
        Throw "The artifacts directory doesn't exist"
    }
    if((Get-ChildItem $ARTIFACTS_DIR).Count -eq 0) {
        Throw "The artifacts directory is empty"
    }
    $buildTime = Get-Date -Format "MM-dd-yyy_HH-mm-ss"
    $remoteBuildDir = "${REMOTE_BASE_DIR}/${buildTime}"
    New-RemoteDirectory -RemoteDirectoryPath $remoteBuildDir
    Copy-FilesToRemoteServer "${ARTIFACTS_DIR}\*" $remoteBuildDir
    New-RemoteSymlink -RemotePath $remoteBuildDir -RemoteSymlinkPath "${REMOTE_BASE_DIR}/latest"
}

try {
    Write-Log "Started generating DC/OS Windows agent blob"
    $startTime = Get-Date
    New-ArtifactsDirectory
    Get-7ZipInstaller
    New-DCOSWindowsAgentBlob
    Publish-BuildArtifacts
    $endTime = Get-Date
    Write-Log "Finished to generate the DC/OS Windows agent blob"
    Write-Log "Job execution stats"
    $endTime - $startTime
} catch {
    Write-Output $_.ToString()
    Write-Output $_.ScriptStackTrace
    exit 1
}
exit 0
