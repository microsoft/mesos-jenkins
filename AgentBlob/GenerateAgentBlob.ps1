
#$BootstrapUrl = "http://52.151.39.54/performance"

function Download-7Zip {
    Write-output "Download-7Zip"
    $urifile = "https://7-zip.org/a/7z1801-x64.msi"
    $uri = [System.Uri]$urifile
    $targetFilename = Split-Path -Path $uri.LocalPath -Leaf
    write-host $targetFilename
    Invoke-WebRequest -UseBasicParsing -Uri $urifile -OutFile .\7z1801-x64.msi
}

function Generate-WindowsAgentBlob {
    Write-output "Generate-WindowsAgentBlob"
    $BootstrapUrl = "http://dcos-win.westus.cloudapp.azure.com/dcos-windows/stable"
    $TARGET_DIR = "C:\agentblob"
    $SCRIPTS_DIR = Join-Path $TARGET_DIR "dcos-windows"
    $SCRIPTS_REPO_URL = "https://github.com/dcos/dcos-windows"
    $sourceFiles = @(
                 "https://download.microsoft.com/download/7/D/D/7DD48DE6-8BDA-47C0-854A-539A800FAA90/wdk/Installers/787bee96dbd26371076b37b13c405890.cab",
                 "https://www.apachelounge.com/download/VC15/binaries/httpd-2.4.33-win64-VC15.zip",
                 "https://download.visualstudio.microsoft.com/download/pr/11687625/2cd2dba5748dc95950a5c42c2d2d78e4/VC_redist.x64.exe",
                 "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe",
                 "http://dcos-win.westus.cloudapp.azure.com/downloads/docker/18.03.1-ce/docker.exe",
                 "http://dcos-win.westus.cloudapp.azure.com/downloads/docker/18.03.1-ce/dockerd.exe",
                 "http://dcos-win.westus.cloudapp.azure.com/downloads/service-wrapper.exe",
                 "$BootstrapUrl/mesos.zip",
                 "$BootstrapUrl/dcos-net.zip",
                 "$BootstrapUrl/metrics.zip",
                 "$BootstrapUrl/diagnostics.zip"
                )

    Remove-item $TARGET_DIR -Recurse -ErrorAction SilentlyContinue
    New-Item -ItemType "Directory" -Path $TARGET_DIR -ErrorAction SilentlyContinue
    foreach ($urifile in $sourceFiles) {
        write-host "Downloading $urifile"
        $uri = [System.Uri]$urifile
        $targetFilename = Split-Path -Path $uri.LocalPath -Leaf
        write-host $targetFilename

        $targetPath = Join-Path $TARGET_DIR $targetFilename
        Remove-item $targetFilename -ErrorAction SilentlyContinue
        Invoke-WebRequest -UseBasicParsing -Uri $urifile -OutFile $targetPath

        # exact devcon
        if ($targetFilename -eq "787bee96dbd26371076b37b13c405890.cab") {
            $devConDir = $TARGET_DIR
            $devConFile = "filbad6e2cce5ebc45a401e19c613d0a28f"
            expand.exe $targetPath -F:$devConFile $devConDir
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
    $p = Start-Process -FilePath 'git.exe' -Wait -PassThru -NoNewWindow -ArgumentList @('clone', '-b perf', $SCRIPTS_REPO_URL, $SCRIPTS_DIR) 
    if($p.ExitCode -ne 0) {
        Throw "Failed to clone $SCRIPTS_REPO_URL repository"
    }

    Write-Output "$((Get-Date -Format g).ToString()): generate blob"
    Remove-item -Path .\windowsAgentBlob.zip -Force  -ErrorAction SilentlyContinue
    Compress-Archive -Path $TARGET_DIR -DestinationPath .\windowsAgentBlob.zip
}

Measure-Command {
    Generate-WindowsAgentBlob
    Download-7Zip
}


