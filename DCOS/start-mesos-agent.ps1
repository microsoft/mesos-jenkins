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
    $agent_ip = (Get-NetIPAddress -InterfaceAlias 'Ethernet 2' -AddressFamily IPv4).IPAddress
}

# Start mesos agent process
$mesos_agent = "$binaries_path\mesos-agent.exe"
$argument_list = @("--master=zk://$master_ip:2181/mesos", "--work_dir=$workingdir_path", "--runtime_dir=$workingdir_path", "--launcher_dir=$binaries_path", "--isolation=windows/cpu,filesystem/windows", "--ip=$agent_ip", "--containerizers=docker,mesos", "--log_dir=$mesoslog_path\")

Start-Process -FilePath $mesos_agent -ArgumentList $argument_list -RedirectStandardOutput "$mesoslog_path\agent-stdout.log" -RedirectStandardError "$mesoslog_path\agent-err.log" -PassThru

