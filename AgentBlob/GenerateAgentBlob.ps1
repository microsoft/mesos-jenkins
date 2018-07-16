Param(
    [string]$DiagnosticsPackageUrl="http://dcos-win.westus.cloudapp.azure.com/artifacts/dcos-diagnostics-build/latest-diagnostics-build/binaries/diagnostics.zip",
    [string]$MetricsPackageUrl="http://dcos-win.westus.cloudapp.azure.com/artifacts/dcos-metrics-build/latest-metrics-build/binaries/metrics.zip",
    [string]$MesosPackageUrl="http://dcos-win.westus.cloudapp.azure.com/artifacts/dcos-mesos-build/latest-mesos-build/binaries/mesos-binaries.zip",
    [string]$DcosNetPackageUrl="http://dcos-win.westus.cloudapp.azure.com/artifacts/dcos-net-build/latest-net-build/release.zip",
    [string]$SpartanPackageUrl="http://dcos-win.westus.cloudapp.azure.com/artifacts/dcos-spartan-build/latest-spartan-build/release.zip",
    [string]$DockerBinariesBaseUrl="http://dcos-win.westus.cloudapp.azure.com/downloads/docker/18-03-1-ee-1",
    [string]$ParametersFile="${env:TEMP}\generate-blob-parameters.json",
    [string]$GithubPRHeadSha
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
    "handles.exe"                 = "http://dcos-win.westus.cloudapp.azure.com/downloads/handles.exe"
}
$ARTIFACTS_DIR = Join-Path $env:WORKSPACE "artifacts"
$7ZIP_DOWNLOAD_URL = "https://7-zip.org/a/7z1801-x64.msi"
$WINDOWS_AGENT_BLOB_FILE_NAME = "windowsAgentBlob.zip"
$global:PARAMETERS = @{
    "BUILD_STATUS" = $null
    "ARTIFACTS_DIR" = $ARTIFACTS_DIR
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
    Start-FileDownload -URL $7ZIP_DOWNLOAD_URL -Destination $targetPath
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
        Start-FileDownload -URL $fileUri -Destination $targetPath
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
    # - Fetch dcos-windows/scripts directory
    Write-Log "Fetching dcos-windows/scripts"
    if($GithubPRHeadSha) {
        $fileName = "${GithubPRHeadSha}"
    } else {
        $fileName = "master"
    }
    $dcoswindowsZipUrl = "{0}/archive/{1}.zip" -f @($DCOS_WINDOWS_GIT_URL, $fileName)
    $dcoswindowsTmpDir = Join-Path $blobDir "dcos-windows-tmp"
    $dcoswindowsArchive = Join-Path $blobDir "dcos-windows.zip"
    $setupScripts = Join-Path $blobDir "scripts"
    if(Test-Path $setupScripts) {
        Remove-Item -Recurse -Force -Path $setupScripts
    }
    Start-FileDownload -URL $dcoswindowsZipUrl -Destination $dcoswindowsArchive
    Expand-Archive -Path $dcoswindowsArchive -DestinationPath $dcoswindowsTmpDir -Force
    Remove-Item -Force -Path $dcoswindowsArchive
    Copy-Item -Recurse -Path "${dcoswindowsTmpDir}\dcos-windows-${fileName}\scripts" -Destination $setupScripts
    New-Item -ItemType Directory -Path "${blobDir}\dcos-windows"
    Copy-Item -Recurse -Force -Path $setupScripts -Destination "${blobDir}\dcos-windows\"
    # - Copy the main init script
    $initScript = "${dcoswindowsTmpDir}\dcos-windows-${fileName}\DCOSWindowsAgentSetup.ps1"
    Copy-Item -Path $initScript -Destination "$($global:PARAMETERS['ARTIFACTS_DIR'])\DCOSWindowsAgentSetup.ps1"
    # - Copy the pre-provision scripts for the CI
    Copy-Item -Recurse -Path "$PSScriptRoot\..\DCOS\preprovision" -Destination "$($global:PARAMETERS['ARTIFACTS_DIR'])\preprovision"
    Remove-Item -Recurse -Force -Path $dcoswindowsTmpDir

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
    Write-Log "Started generating DC/OS Windows agent blob"
    $startTime = Get-Date
    New-ParametersFile
    New-ArtifactsDirectory
    Get-7ZipInstaller
    New-DCOSWindowsAgentBlob
    $endTime = Get-Date
    Write-Log "Finished to generate the DC/OS Windows agent blob"
    Write-Log "Job execution stats"
    $endTime - $startTime
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
