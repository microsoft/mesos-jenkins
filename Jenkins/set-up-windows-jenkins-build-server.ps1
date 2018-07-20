$ErrorActionPreference = "Stop"

$PACKAGES_DIRECTORY = Join-Path $env:TEMP "packages"
$PACKAGES = @{
    "java_8" = @{
        "url" = $null
        "local_file" = Join-Path $PACKAGES_DIRECTORY "java_8.exe"
    }
    "vs_2017" = @{
        "url" = "https://download.visualstudio.microsoft.com/download/pr/11886246/045b56eb413191d03850ecc425172a7d/vs_Community.exe"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "vs_2017_community.exe"
    }
    "git" = @{
        "url" = "http://dcos-win.westus.cloudapp.azure.com/downloads/git-64-bit.exe"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "git.exe"
    }
    "cmake" = @{
        "url" = "https://cmake.org/files/v3.9/cmake-3.9.0-win64-x64.msi"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "cmake.msi"
    }
    "patch" = @{
        "url" = "https://github.com/mesos/3rdparty/raw/master/patch-2.5.9-7-setup.exe"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "patch.exe"
    }
    "python36" = @{
        "url" = "https://www.python.org/ftp/python/3.6.5/python-3.6.5-amd64.exe"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "python-3.6.exe"
    }
    "putty" = @{
        "url" = "https://the.earth.li/~sgtatham/putty/0.70/w64/putty-64bit-0.70-installer.msi"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "putty.msi"
    }
    "7z" = @{
        "url" = "https://www.7-zip.org/a/7z1801-x64.exe"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "7z.exe"
    }
    "go" = @{
        "url" = "https://dl.google.com/go/go1.9.4.windows-amd64.msi"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "go.msi"
    }
    "msys2" = @{
        "url" = "http://dcos-win.westus.cloudapp.azure.com/downloads/msys2-x64.zip"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "msys2.zip"
    }
    "dig" = @{
        "url" = "http://dcos-win.westus.cloudapp.azure.com/downloads/dig-x64.zip"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "dig.zip"
    }
    "2012_runtime" = @{
        "url" = "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x64.exe"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "vcredist_2012.exe"
    }
    "2013_runtime" = @{
        "url" = "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "vcredist_2013.exe"
    }
    "otp_193" = @{
        "url" = "http://dcos-win.westus.cloudapp.azure.com/downloads/erl8.3.zip"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "erl8.3.zip"
    }
    "otp_202" = @{
        "url" = "http://dcos-win.westus.cloudapp.azure.com/downloads/erl9.2.zip"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "erl9.2.zip"
    }
    "maven" = @{
        "url" = "http://mirrors.m247.ro/apache/maven/maven-3/3.5.3/binaries/apache-maven-3.5.3-bin.zip"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "maven.zip"
    }
    "openssl" = @{
        "url" = "https://slproweb.com/download/Win64OpenSSL-1_0_2o.exe"
        "local_file" = Join-Path $PACKAGES_DIRECTORY "openssl.exe"
    }
}


function Start-LocalPackagesDownload {
    Write-Output "Downloading all the packages to local directory: $PACKAGES_DIRECTORY"
    if(!(Test-Path $PACKAGES_DIRECTORY)) {
        New-Item -ItemType "Directory" -Path $PACKAGES_DIRECTORY
    }
    foreach($pkg in $PACKAGES.Keys) {
        if(!$PACKAGES[$pkg]["url"]) {
            if(!(Test-Path $PACKAGES[$pkg]["local_file"])) {
                Throw "Package $pkg must be manually downloaded to: $($PACKAGES[$pkg]["local_file"])"
            }
            continue
        }
        Write-Output "Downloading: $($PACKAGES[$pkg]["url"])"
        Start-BitsTransfer $PACKAGES[$pkg]["url"] -Destination $PACKAGES[$pkg]["local_file"]
    }
    Write-Output "Finished downloading all the packages"
}

function Add-ToSystemPath {
    Param(
        [Parameter(Mandatory=$false)]
        [string[]]$Path
    )
    if(!$Path) {
        return
    }
    $systemPath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine').Split(';')
    $currentPath = $env:PATH.Split(';')
    foreach($p in $Path) {
        if($p -notin $systemPath) {
            $systemPath += $p
        }
        if($p -notin $currentPath) {
            $currentPath += $p
        }
    }
    $env:PATH = $currentPath -join ';'
    setx.exe /M PATH ($systemPath -join ';')
    if($LASTEXITCODE) {
        Throw "Failed to set the new system path"
    }
}

function Set-EnvironmentVariable {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [string]$Value,
        [Parameter(Mandatory=$false)]
        [switch]$SystemWide=$false
    )
    $params = @()
    if($SystemWide) {
        $params += @("/M")
    }
    $params += @($Name, "`"$Value`"")
    $p = Start-Process -FilePath "setx.exe" -Wait -PassThru -NoNewWindow -ArgumentList $params
    if($p.ExitCode -ne 0) {
        Throw "Failed to set environment variable $Name"
    }
    [System.Environment]::SetEnvironmentVariable($Name, $Value)
}

function Install-CITool {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$InstallerPath,
        [Parameter(Mandatory=$false)]
        [string]$InstallDirectory,
        [Parameter(Mandatory=$false)]
        [string[]]$ArgumentList,
        [Parameter(Mandatory=$false)]
        [string[]]$EnvironmentPath
    )
    if($InstallDirectory -and (Test-Path $InstallDirectory)) {
        Write-Output "$InstallerPath is already installed."
        Add-ToSystemPath -Path $EnvironmentPath
        return
    }
    $parameters = @{
        'FilePath' = $InstallerPath
        'Wait' = $true
        'PassThru' = $true
    }
    if($ArgumentList) {
        $parameters['ArgumentList'] = $ArgumentList
    }
    if($InstallerPath.EndsWith('.msi')) {
        $parameters['FilePath'] = 'msiexec.exe'
        $parameters['ArgumentList'] = @("/i", $InstallerPath) + $ArgumentList
    }
    Write-Output "Installing $InstallerPath"
    $p = Start-Process @parameters
    if($p.ExitCode -ne 0) {
        Throw "Failed to install: $InstallerPath"
    }
    Add-ToSystemPath -Path $EnvironmentPath
    Write-Output "Successfully installed: $InstallerPath"
}

function Install-ZipCITool {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$ZipPath,
        [Parameter(Mandatory=$true)]
        [string]$InstallDirectory,
        [Parameter(Mandatory=$false)]
        [string[]]$EnvironmentPath
    )
    if(Test-Path $InstallDirectory) {
        Write-Output "$ZipPath is already installed."
        Add-ToSystemPath -Path $EnvironmentPath
        return
    }
    New-Item -ItemType "Directory" -Path $InstallDirectory
    $extension = $ZipPath.Split('.')[-1]
    if($extension -ne "zip") {
        Throw "ERROR: $ZipPath is not a zip package"
    }
    7z.exe x $ZipPath -o"$InstallDirectory" -y
    if($LASTEXITCODE) {
        Throw "ERROR: Failed to extract $ZipPath to $InstallDirectory"
    }
    Add-ToSystemPath $EnvironmentPath
}

function Install-VisualStudio2017 {
    $installDir = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\2017\Community"
    $installerArguments = @(
        "--add", "Microsoft.VisualStudio.Workload.NativeDesktop",
        "--quiet", "--wait", "--includeRecommended"
    )
    Install-CITool -InstallerPath $PACKAGES["vs_2017"]["local_file"] `
                   -InstallDirectory $installDir `
                   -ArgumentList $installerArguments
    $installerArguments = @(
        "--add", "Microsoft.VisualStudio.Component.Windows81SDK",
        "--quiet", "--wait", "--includeRecommended"
    )
    Install-CITool -InstallerPath $PACKAGES["vs_2017"]["local_file"] `
                   -ArgumentList $installerArguments
}

function Install-Docker {
    $service = Get-Service "Docker" -ErrorAction SilentlyContinue
    if($service) {
        Stop-Service "Docker"
        sc.exe delete "Docker"
        if($LASTEXITCODE) {
            Throw "ERROR: Failed to delete existing Docker service"
        }
    }
    $dockerRegKey = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\docker"
    if(Test-Path $dockerRegKey) {
        Remove-Item $dockerRegKey
    }
    $installDir = Join-Path $env:ProgramFiles "Docker"
    $dockerUrl = "http://dcos-win.westus.cloudapp.azure.com/downloads/docker/18-03-1-ee-1/docker.exe"
    $dockerdUrl = "http://dcos-win.westus.cloudapp.azure.com/downloads/docker/18-03-1-ee-1/dockerd.exe"
    Start-BitsTransfer $dockerUrl -Destination "$installDir\docker.exe"
    Start-BitsTransfer $dockerdUrl -Destination "$installDir\dockerd.exe"
    Add-ToSystemPath -Path $installDir
    dockerd.exe --register-service
    if($LASTEXITCODE) {
        Throw "ERROR: Failed to register Docker as a Windows service"
    }
    Start-Service "Docker"
}

function Install-Git {
    $installDir = Join-Path $env:ProgramFiles "Git"
    Install-CITool -InstallerPath $PACKAGES["git"]["local_file"] `
                   -InstallDirectory $installDir `
                   -ArgumentList @("/SILENT") `
                   -EnvironmentPath @("$installDir\cmd", "$installDir\bin")
    git.exe config --global core.autocrlf true
    if($LASTEXITCODE) {
        Throw "Failed to set git global config core.autocrlf true"
    }
}

function Install-CMake {
    $installDir = Join-Path $env:ProgramFiles "CMake"
    Install-CITool -InstallerPath $PACKAGES["cmake"]["local_file"] `
                   -InstallDirectory $installDir `
                   -ArgumentList @("/quiet") `
                   -EnvironmentPath @("$installDir\bin")
}

function Install-Patch {
    $installDir = Join-Path ${env:ProgramFiles(x86)} "GnuWin32"
    Install-CITool -InstallerPath $PACKAGES["patch"]["local_file"] `
                   -InstallDirectory $installDir `
                   -ArgumentList @("/VERYSILENT","/SUPPRESSMSGBOXES","/SP-") `
                   -EnvironmentPath @("$installDir\bin")
}

function Install-Python36 {
    $installDir = Join-Path $env:ProgramFiles "Python36"
    Install-CITool -InstallerPath $PACKAGES["python36"]["local_file"] `
                   -InstallDirectory $installDir `
                   -ArgumentList @("/quiet", "InstallAllUsers=1", "TargetDir=`"$installDir`"") `
                   -EnvironmentPath @($installDir, "$installDir\Scripts")
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name LongPathsEnabled -Value 1
}

function Install-Putty {
    $installDir = Join-Path $env:ProgramFiles "PuTTY"
    Install-CITool -InstallerPath $PACKAGES["putty"]["local_file"] `
                   -InstallDirectory $installDir `
                   -ArgumentList @("/q") `
                   -EnvironmentPath @($installDir)
}

function Install-7Zip {
    $installDir = Join-Path $env:ProgramFiles "7-Zip"
    Install-CITool -InstallerPath $PACKAGES["7z"]["local_file"] `
                   -InstallDirectory $installDir `
                   -ArgumentList @("/S") `
                   -EnvironmentPath @($installDir)
}

function Install-Golang {
    $installDir = Join-Path $env:SystemDrive "Go"
    Set-EnvironmentVariable -Name "GOROOT" -Value $installDir -SystemWide
    Install-CITool -InstallerPath $PACKAGES["go"]["local_file"] `
                   -InstallDirectory $installDir `
                   -ArgumentList @("/qb") `
                   -EnvironmentPath @("$installDir\bin")
}

function Install-Java18 {
    $installDir = Join-Path $env:ProgramFiles "Java"
    Install-CITool -InstallerPath $PACKAGES["java_8"]["local_file"] `
                   -InstallDirectory $installDir `
                   -ArgumentList @("/s") `
                   -EnvironmentPath @("${env:ProgramData}\Oracle\Java\javapath")
    $javaHome = (Get-ChildItem "$installDir\jdk1.8*").FullName
    if(!$javaHome) {
        Throw "ERROR: Cannot find JAVA_HOME"
    }
    Set-EnvironmentVariable -Name "JAVA_HOME" -Value $javaHome -SystemWide
    $jvmDLL = Join-Path $javaHome "jre\bin\server\jvm.dll"
    Set-EnvironmentVariable -Name "JAVA_JVM_LIBRARY" -Value $jvmDLL -SystemWide
    Add-ToSystemPath -Path "$javaHome\jre\bin"
}

function Install-OpenSSL {
    $installDir = Join-Path $env:ProgramFiles "OpenSSL"
    Install-CITool -InstallerPath $PACKAGES["openssl"]["local_file"] `
                   -InstallDirectory $installDir `
                   -ArgumentList @("/silent", "/verysilent", "/sp-", "/suppressmsgboxes", "/DIR=`"$installDir`"") `
                   -EnvironmentPath @("$installDir\bin")
}

function Install-Maven {
    $installDir = Join-Path $env:ProgramFiles "Maven"
    try {
        Install-ZipCITool -ZipPath $PACKAGES["maven"]["local_file"] `
                          -InstallDirectory $installDir `
                          -EnvironmentPath @("$installDir\bin")
    } catch {
        Remove-Item -Recurse -Force $installDir
        Throw
    }
    if(Test-Path "$installDir\apache-maven-*\*") {
        Move-Item "$installDir\apache-maven-*\*" "$installDir\"
        Remove-Item "$installDir\apache-maven-*"
    }
}

function Install-Msys2 {
    $installDir = Join-Path $env:ProgramFiles "msys2"
    try {
        Install-ZipCITool -ZipPath $PACKAGES["msys2"]["local_file"] `
                          -InstallDirectory $installDir `
                          -EnvironmentPath @("$installDir\usr\bin")
    } catch {
        Remove-Item -Recurse -Force $installDir
        Throw
    }
    pacman.exe -Syu make --noconfirm
    if($LASTEXITCODE) {
        Throw "ERROR: Failed to install make via msys2 pacman"
    }
}

function Install-Dig {
    Install-CITool -InstallerPath $PACKAGES["2012_runtime"]["local_file"] `
                   -ArgumentList @("/install", "/passive")
    $installDir = Join-Path $env:ProgramFiles "Dig"
    try {
        Install-ZipCITool -ZipPath $PACKAGES["dig"]["local_file"] `
                          -InstallDirectory $installDir `
                          -EnvironmentPath @("$installDir\bin")
    } catch {
        Remove-Item -Recurse -Force $installDir
        Throw
    }
}

function Install-OPT193 {
    Install-CITool -InstallerPath $PACKAGES["2013_runtime"]["local_file"] `
                   -ArgumentList @("/install", "/passive")
    $installDir = Join-Path $env:ProgramFiles "erl8.3"
    try {
        Install-ZipCITool -ZipPath $PACKAGES["otp_193"]["local_file"] `
                          -InstallDirectory $installDir `
                          -EnvironmentPath @("$installDir\bin")
    } catch {
        Remove-Item -Recurse -Force $installDir
        Throw
    }
    $config = @(
        "[erlang]",
        "Bindir=$("$installDir\erts-8.3\bin" -replace '\\', '\\')",
        "Progname=erl",
        "Rootdir=$($installDir -replace '\\', '\\')"
    )
    Set-Content -Path "$installDir\bin\erl.ini" -Value $config
    Set-Content -Path "$installDir\erts-8.3\bin\erl.ini" -Value $config
}

function Install-OPT202 {
    Install-CITool -InstallerPath $PACKAGES["2013_runtime"]["local_file"] `
                   -ArgumentList @("/install", "/passive")
    $installDir = Join-Path $env:ProgramFiles "erl9.2"
    try {
        Install-ZipCITool -ZipPath $PACKAGES["otp_202"]["local_file"] `
                          -InstallDirectory $installDir `
                          -EnvironmentPath @("$installDir\bin")
    } catch {
        Remove-Item -Recurse -Force $installDir
        Throw
    }
    $config = @(
        "[erlang]",
        "Bindir=$("$installDir\erts-9.2\bin" -replace '\\', '\\')",
        "Progname=erl",
        "Rootdir=$($installDir -replace '\\', '\\')"
    )
    Set-Content -Path "$installDir\bin\erl.ini" -Value $config
    Set-Content -Path "$installDir\erts-9.2\bin\erl.ini" -Value $config
}

function Install-PowerShellModules {
    Install-Module -Name "Pester" -SkipPublisherCheck -Force -Confirm:$false
    Install-Module AzureRM -Force -Confirm:$false
}


try {
    Start-LocalPackagesDownload
    Install-VisualStudio2017
    Install-Docker
    Install-Git
    Install-CMake
    Install-Patch
    Install-Python36
    Install-Putty
    Install-Golang
    Install-Java18
    Install-OpenSSL
    Install-7Zip
    Install-Maven
    Install-Msys2
    Install-Dig
    Install-OPT193
    Install-OPT202
    Install-PowerShellModules
    # TODO: Configure git user and e-mail
    # TODO: Generate SSH keypair
    # TODO: Authorize Git SSH Keys
} catch {
    Write-Output $_.ToString()
    Write-Output $_.ScriptStackTrace
    exit 1
}
exit 0
