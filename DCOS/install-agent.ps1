Param(
    [Parameter(Mandatory=$true)]
    [String]$PatchID,
    [Parameter(Mandatory=$true)]
    [String]$Branch
)
$ErrorActionPreference = "Stop"

# Parameters
$binaries_url = "http://104.210.40.105/binaries/$Branch/$PatchID/binaries-$PatchID.zip"
$repo_url = "https://github.com/capsali/mesos-jenkins"
$mesos_path = "C:\mesos"
$binaries_path = "$mesos_path\bin"
$workingdir_path = "$mesos_path\work"
$repo_path = "C:\mesos-jenkins"
$tempDir = $env:temp

# Create paths
New-Item -ItemType Directory -ErrorAction SilentlyContinue -Path $mesos_path
New-Item -ItemType Directory -ErrorAction SilentlyContinue -Path $binaries_path
New-Item -ItemType Directory -ErrorAction SilentlyContinue -Path $workingdir_path

# Download and install Git
$git_url = "http://81.181.181.155:8081/shared/kits/Git-2.13.2-64-bit.exe"
$has_git = Test-Path -Path "C:\Program Files\Git"
if (! $has_git) {
    write-host "No git installation detected. Will install"
    write-host "Downloading installer"
    Invoke-WebRequest -UseBasicParsing -Uri $git_url -OutFile "$tempDir\git.exe"
    write-host "Installing git"
    Start-Process -FilePath $tempDir\git.exe -ArgumentList "/SILENT" -Wait -PassThru
}

# Download and install putty for scp
$putty_url = "https://the.earth.li/~sgtatham/putty/0.70/w64/putty-64bit-0.70-installer.msi"
$has_putty = Test-Path -Path "C:\Program Files\PuTTY"
if (! $has_putty) {
    write-host "No putty installation detecte. Will install"
    write-host "Downloading installer"
    Invoke-WebRequest -UseBasicParsing -Uri $putty_url -OutFile "$tempDir\putty.msi"
    write-host "Installing putty"
    Start-Process -FilePath msiexec.exe -ArgumentList "/q","/i","$tempDir\putty.msi" -Wait -PassThru
}

# Add git to env path
$env:path += ";C:\Program Files\Git\cmd;C:\Program Files\Git\bin;C:\Program Files\PuTTY;"

# Clone the mesos-jenkins repo
$has_repo = Test-Path -Path $repo_path
if (! $has_repo) {
    Write-Host "Cloning mesos-jenkins repo"
    & git clone $repo_url $repo_path
}
else {
    pushd $repo_path
    git checkout $branch
    git pull
    popd
}

# Check if binaries are present
$check_binaries = Test-Path -Path "$binaries_path\mesos-agent.exe"
if ($check_binaries) {
    Write-Host "Binaries exist."
    exit 0
}

# Download the binaries
Write-Host "Downloading mesos binaries from $binaries_url"
Invoke-WebRequest -UseBasicParsing -Uri $binaries_url -OutFile "$tempDir\binaries.zip"
Write-Host "Extracting binaries archive in $binaries_path"
#[System.IO.Compression.ZipFile]::ExtractToDirectory("$tempDir\binaries.zip", "$binaries_path\")
Expand-Archive -LiteralPath "$tempDir\binaries.zip" -DestinationPath "$binaries_path\"

# Open firewall port 5051 on agent node
Write-Host "Opening port 5051"
New-NetFirewallRule -DisplayName "Allow inbound TCP Port 5051" -Direction inbound -LocalPort 5051 -Protocol TCP -Action Allow

Write-Host "Finished preparing agent system"