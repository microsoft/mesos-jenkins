$timeout_30s = New-TimeSpan -Seconds 30
$timeout_2mins = New-TimeSpan -Minutes 2

foreach($name in "dcos-mesos-slave.service", "dcos-mesos-slave-public.service") {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if($svc) {
        $mesosServiceName = $name
        break
    }
}

if(!$mesosServiceName) {
    Throw "Cannot find the Mesos slave agent"
}

$ParentProcessIds = Get-CimInstance -Class Win32_Process -Filter "Name = 'mesos-agent.exe'"
$ParentPID = $ParentProcessIds[0].ParentProcessId
taskkill /PID $ParentPID /F 2>&1 >$null
taskkill /IM mesos-agent.exe /F 2>&1 >$null

if ($LastExitCode -eq 0) {
    $mesosServiceObj = Get-Service $mesosServiceName
    $mesosServiceObj.WaitForStatus('Stopped',$timeout_2mins)
    if ($mesosServiceObj.Status -ne 'Stopped') { 
        Write-Output "FAILURE"
    } else {
        Write-Output "SUCCESS"
    }
} elseif ($LastExitCode -eq 128) {
    Write-Output "No such process mesos-agent.exe"
    exit 1
} else {
    Write-Output "Unexpected exit code for taskkill: $LastExitCode"
    exit 1
}