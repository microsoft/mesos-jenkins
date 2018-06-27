taskkill /IM mesos-agent.exe /F 2>&1 >$null
if ($LastExitCode -eq 0) {
    $mesosServiceObj = Get-Service dcos-mesos-slave
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