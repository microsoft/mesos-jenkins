
# This is a script to package all the DC/OS Windows agent components into single zip 
# file, called WindowsAgentBlob, for speeding up the Windows agent's setup.
# 7-Zip package was added for faster unzipping purpose

$sourceFiles = @{
                  "MicrosoftWDKInstallers.cab" = "https://download.microsoft.com/download/7/D/D/7DD48DE6-8BDA-47C0-854A-539A800FAA90/wdk/Installers/787bee96dbd26371076b37b13c405890.cab";
                  "httpd-2.4.33-win64-VC15.zip" = "https://www.apachelounge.com/download/VC15/binaries/httpd-2.4.33-win64-VC15.zip";
                  "VC_redist_2013_x64.exe" =  "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe";
                  "VC_redist_2017_x64.exe" = "https://download.visualstudio.microsoft.com/download/pr/11687625/2cd2dba5748dc95950a5c42c2d2d78e4/VC_redist.x64.exe";
                  "docker.exe"       = "http://dcos-win.westus.cloudapp.azure.com/downloads/docker/18.03.1-ce/docker.exe";
                  "dockerd.exe"      = "http://dcos-win.westus.cloudapp.azure.com/downloads/docker/18.03.1-ce/dockerd.exe";
                  "service-wrapper.exe" = "http://dcos-win.westus.cloudapp.azure.com/downloads/service-wrapper.exe";
                  "mesos.zip"       =  "http://dcos-win.westus.cloudapp.azure.com/mesos-build/apache/latest/binaries/mesos-binaries.zip";
                  "dcos-net.zip"    =  "http://dcos-win.westus.cloudapp.azure.com/net-build/dcos/latest/release.zip";
                  "metrics.zip"     = "http://dcos-win.westus.cloudapp.azure.com/metrics-build/dcos/latest/binaries/metrics.zip";
                  "diagnostics.zip" = "http://dcos-win.westus.cloudapp.azure.com/diagnostics-build/dcos/latest/binaries/diagnostics.zip";
                  # The following file is a big file and it's only needed for DC/OS 1.10. We can remove it should we decided to remove support for 1.10
                  "spartan.zip"     = "http://dcos-win.westus.cloudapp.azure.com/spartan-build/master/latest/release.zip" 
                }
$7ZipUri = "https://7-zip.org/a/7z1801-x64.msi"

$WINDOW_AGENT_BLOB_FILE_NAME = "windowsAgentBlob.zip"
$ErrorActionPreference = "Stop"
$TARGET_DIR = Join-Path $env:WORKSPACE "agentblob"

function Download-7Zip {
    Write-Output "Download-7Zip"
    $uri = [System.Uri]$7ZipUri
    $targetFilename = Split-Path -Path $uri.LocalPath -Leaf
    $targetPath = Join-Path $env:TEMP $targetFilename
    Write-Output $targetPath
    Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $targetPath
}

function Generate-WindowsAgentBlob {
    Write-Output "Generate-WindowsAgentBlob"
    $BootstrapUrl = "http://dcos-win.westus.cloudapp.azure.com/dcos-windows/stable"
    $SCRIPTS_DIR = Join-Path $TARGET_DIR "dcos-windows"
    $SCRIPTS_REPO_URL = "https://github.com/dcos/dcos-windows"
    Remove-item $TARGET_DIR -Recurse -ErrorAction SilentlyContinue
    New-Item -ItemType "Directory" -Path $TARGET_DIR -ErrorAction SilentlyContinue

    foreach($key in $sourceFiles.keys) {
        $urifile = $($sourceFiles.Item($key))
        Write-Output "Downloading $urifile"
        $uri = [System.Uri]$urifile
        $targetFilename = $key
        Write-Output $targetFilename

        $targetPath = Join-Path $TARGET_DIR $targetFilename
        Remove-item $targetFilename -ErrorAction SilentlyContinue
        Invoke-WebRequest -UseBasicParsing -Uri $urifile -OutFile $targetPath

        # exact devcon
        if ($targetFilename -eq "MicrosoftWDKInstallers.cab") {
            $devConDir = $TARGET_DIR
            $devConFile = "filbad6e2cce5ebc45a401e19c613d0a28f"
            expand.exe $targetPath -F:$devConFile $devConDir
            if($LASTEXITCODE) {
                Throw "Failed to expand DevCon archive"
            }
            $devConBinary = Join-Path $TARGET_DIR "devcon.exe"
            $devConBinaryFullpath = Join-Path $TARGET_DIR $devConFile
            Remove-item -Path $devConBinary -Force -ErrorAction SilentlyContinue
            Move-Item $devConBinaryFullpath  $devConBinary 
            Remove-item -Path $targetFilename -Force  -ErrorAction SilentlyContinue
            Remove-item -Path $targetPath -Force  -ErrorAction SilentlyContinue
        }
    }

    Write-Output "$((Get-Date -Format g).ToString()): git clone dcos-windows repo"
    if(Test-Path $SCRIPTS_DIR) {
        Remove-Item -Recurse -Force -Path $SCRIPTS_DIR
    }
    $p = Start-Process -FilePath 'git.exe' -Wait -PassThru -NoNewWindow -ArgumentList @('clone', $SCRIPTS_REPO_URL, $SCRIPTS_DIR) 
    if($p.ExitCode -ne 0) {
        Throw "Failed to clone $SCRIPTS_REPO_URL repository"
    }

    Write-Output "$((Get-Date -Format g).ToString()): generate blob"

    $blobTargetPath = Join-Path $env:TEMP $WINDOW_AGENT_BLOB_FILE_NAME 
    Remove-item -Path $blobTargetPath -Force  -ErrorAction SilentlyContinue
    Compress-Archive -Path $TARGET_DIR -DestinationPath $blobTargetPath -Force
}

try {
    Measure-Command {
        Generate-WindowsAgentBlob
        Download-7Zip
    }
} catch {
    Write-Output $_.ToString()
    Write-Output $_.ScriptStackTrace
    exit 1
} finally {
    Remove-Item -Recurse -Force $TARGET_DIR  -ErrorAction SilentlyContinue
}
exit 0
