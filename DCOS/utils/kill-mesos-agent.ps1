foreach($name in "dcos-mesos-slave", "dcos-mesos-slave-public") {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if($svc) {
        $mesosServiceName = $name
        break
    }
}
if(!$mesosServiceName) {
    Throw "Cannot find the Mesos slave agent"
}

taskkill /IM mesos-agent.exe /F 2>&1 >$null
if ($LastExitCode -eq 0) {
    $mesosServiceObj = Get-Service $mesosServiceName
    $mesosServiceObj.WaitForStatus('Running','00:01:00')
    if ($mesosServiceObj.Status -ne 'Running') { 
        Write-Output "FAILURE"
    } else {
        Write-Output "SUCCESS"
    }
} elseif ($LastExitCode -eq 128) {
    Write-Output "No such process mesos-agent.exe"
} else {
    Write-Output "Unexpected exit code for taskkill: $LastExitCode"
}