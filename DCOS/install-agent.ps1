Param(
    [Parameter(Mandatory=$true)]
    [String]$PatchID,
    [Parameter(Mandatory=$true)]
    [String]$Branch
)
$ErrorActionPreference = "Stop"

# Parameters
$git_url = "http://81.181.181.155:8081/shared/kits/Git-2.13.2-64-bit.exe"
$binaries_url = "http://104.210.40.105/binaries/$branch/$patchID/binaries-$patchID.zip"
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
$has_git = Test-Path -Path $git_path
if (! $has_git) {
    write-host "No git installation detected. Will install"
    write-host "Downloading installer"
    Invoke-WebRequest -UseBasicParsing -Uri $git_url -OutFile "$tempDir\git.exe"
    write-host "Installing git"
    Start-Process -FilePath $tempDir\git.exe -ArgumentList "/SILENT" -Wait -PassThru
}

# Add git to env path
$env:path += ";C:\Program Files\Git\cmd;C:\Program Files\Git\bin;"

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

# Download the binaries
Write-Host "Downloading mesos binaries from $binaries_url"
Invoke-WebRequest -UseBasicParsing -Uri $binaries_url -OutFile "$tempDir\binaries.zip"
Write-Host "Extracting binaries archive in $binaries_path"
[System.IO.Compression.ZipFile]::ExtractToDirectory("$tempDir\binaries.zip", "$binaries_url\")



