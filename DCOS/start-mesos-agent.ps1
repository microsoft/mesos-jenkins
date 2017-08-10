Param(
    [Parameter(Mandatory=$true)]
    [String]$master_ip,
    [Parameter(Mandatory=$false)]
    [String]$agent_ip=""
)

$ErrorActionPreference = "Stop"

$mesos_path = "C:\mesos"
$binaries_path = "$mesos_path\bin"
$workingdir_path = "$mesos_path\work"
$mesoslog_path = "$mesos_path\logs"

if (! (Test-Path -Path "$binaries_path\mesos-agent.exe")) {
    Write-Host "Can not find mesos-agent binary. Please run install-agent.ps1 script"
    exit 1
}

if (! $agent_ip) {
    Write-Host "No agent IP specified. Trying to get host IP."
    #$agent_ip = (Get-NetIPAddress -InterfaceAlias 'Ethernet 2' -AddressFamily IPv4).IPAddress
    $agent_ip = ((ipconfig | findstr [0-9].\.)[0]).Split()[-1]
}

# Start mesos agent process
$mesos_agent = "$binaries_path\mesos-agent.exe"
$argument_list = @("--master=zk://${master_ip}:2181/mesos", "--work_dir=${workingdir_path}", "--runtime_dir=${workingdir_path}", "--launcher_dir=${binaries_path}", "--isolation=windows/cpu,filesystem/windows", "--ip=${agent_ip}", "--containerizers=docker,mesos", "--log_dir=${mesoslog_path}\")

# Check if process is running
if (Get-Process -Name mesos-agent -ErrorAction SilentlyContinue) {
    Write-Host "Process is already running"
    exit 0
}

Start-Process -FilePath $mesos_agent -ArgumentList $argument_list -RedirectStandardOutput "$mesoslog_path\agent-stdout.log" -RedirectStandardError "$mesoslog_path\agent-err.log" -NoNewWindow -PassThru

# Wait 20 seconds before checking process
Start-Sleep -s 20

# Check if process is active. If not, clean the working dir and try starting it again
if (! (Get-Process -Name mesos-agent -ErrorAction SilentlyContinue)) {
    # Workaround for powershell Remove-Item bug where we can't remove a folder with symlinks.
    # Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path "${workingdir_path}\*"
    & 'C:\Program Files\Git\usr\bin\rm.exe' -rf $workingdir_path
    New-Item -ItemType Directory -ErrorAction SilentlyContinue -Path $workingdir_path
    Start-Process -FilePath $mesos_agent -ArgumentList $argument_list -RedirectStandardOutput "$mesoslog_path\agent-stdout.log" -RedirectStandardError "$mesoslog_path\agent-err.log" -NoNewWindow -PassThru
}
else {
    Write-Host "Process is running. Finished starting mesos-agent"
    exit 0
}

# Wait 20 more seconds before checking process the last time
Start-Sleep -s 20

# Check the process again and if it is not running error out.
if (Get-Process -Name mesos-agent -ErrorAction SilentlyContinue) {
    Write-Host "Process is running. Finished starting mesos-agent"
    exit 0
}
else {
    Write-Host "Process is not running. Exiting with error"
    exit 1
}

