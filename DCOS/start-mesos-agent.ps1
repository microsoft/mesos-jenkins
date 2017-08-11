Param(
    [Parameter(Mandatory=$true)]
    [String]$master_ip,
    [Parameter(Mandatory=$false)]
    [String]$agent_ip=""
)

$ErrorActionPreference = "Stop"

$repo_path = "C:\mesos-jenkins"
$repo_url = "https://github.com/capsali/mesos-jenkins"
$mesos_path = "C:\mesos"
$binaries_path = "$mesos_path\bin"
$service_path = "$mesos_path\service"
$workingdir_path = "$mesos_path\work"
$mesoslog_path = "$mesos_path\logs"
$templates_path = "C:\mesos-jenkins\templates"

if (! (Test-Path -Path "$binaries_path\mesos-agent.exe")) {
    Write-Host "Can not find mesos-agent binary. Please run install-agent.ps1 script"
    exit 1
}

if (Get-Service -Name mesos-agent -ErrorAction SilentlyContinue) {
    Write-Host "Mesos agent service already installed. Trying to start service"
    Start-Service mesos-agent
    if ((Get-Service -Name mesos-agent).Status -ne "Running") {
        Write-Host "Service failed to start. Exiting"
        exit 1
    }
    
}

# Clone the mesos-jenkins repo
$has_repo = Test-Path -Path $repo_path
if (! $has_repo) {
    Write-Host "Cloning mesos-jenkins repo"
    & git clone $repo_url $repo_path
}
else {
    pushd $repo_path
    git pull
    popd
}

if (! $agent_ip) {
    Write-Host "No agent IP specified. Trying to get host IP."
    #$agent_ip = (Get-NetIPAddress -InterfaceAlias 'Ethernet 2' -AddressFamily IPv4).IPAddress
    $agent_ip = ((ipconfig | findstr [0-9].\.)[0]).Split()[-1]
}

# Create service for mesos-agent.exe
if (! (Test-Path -Path "$service_path")) {
    New-Item -ItemType Directory -ErrorAction SilentlyContinue -Path $service_path
}
# Download service wrapper
Invoke-WebRequest -UseBasicParsing -Uri "http://104.210.40.105/downloads/WinSW.NET4.exe" -OutFile "$service_path\mesos-service.exe"

# Render XML template
[xml]$render_template = cat "$templates_path\mesos-service.xml"
$render_template.configuration.arguments = "--master=zk://${master_ip}:2181/mesos --work_dir=$workingdir_path --runtime_dir=$workingdir_path --launcher_dir=$binaries_path --isolation=windows/cpu,filesystem/windows --ip=$agent_ip --containerizers=docker,mesos --log_dir=$mesoslog_path\"
$render_template.configuration.logpath = "$mesoslog_path"
$render_template.Save("$service_path\mesos-service.xml")

# Install service
#& $service_path\mesos-service.exe install
Start-Process -FilePath $service_path\mesos-service.exe -ArgumentList "install" -NoNewWindow -PassThru -Wait

# Start mesos agent service
Start-Service mesos-agent

# Wait 20 seconds before checking service
Start-Sleep -s 20

# Check if service is running. If not, clean the working dir and try starting it again
if ((Get-Service -Name mesos-agent).Status -ne "Running") {
    # Workaround for powershell Remove-Item bug where we can't remove a folder with symlinks.
    # Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path "${workingdir_path}\*"
    & 'C:\Program Files\Git\usr\bin\rm.exe' -rf $workingdir_path
    New-Item -ItemType Directory -ErrorAction SilentlyContinue -Path $workingdir_path
    Start-Service mesos-agent
}
else {
    Write-Host "Process is running. Finished starting mesos-agent"
    exit 0
}

# Wait 20 more seconds before checking process the last time
Start-Sleep -s 20

# Check the service again and if it is not running error out.
if ((Get-Service -Name mesos-agent).Status -eq "Running") {
    Write-Host "Service is running. Finished starting mesos-agent"
    exit 0
}
else {
    Write-Host "Service is not running. Exiting with error"
    exit 1
}

