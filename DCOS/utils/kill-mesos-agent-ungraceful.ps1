$mesosServiceObj = Stop-Service dcos-mesos-slave -PassThru
$mesosServiceObj.WaitForStatus('Stopped','00:00:30')
if ($mesosServiceObj.Status -ne 'Stopped') {
    Write-Output "Failed to stop the service"
    exit 1
}

$check = sc.exe qc dcos-mesos-slave | Select-String "--recovery_timeout=1mins"
if ($LastExitCode -ne 0) {
    Write-Output "Unexpected exit code for sc.exe: $LastExitCode. Aborting"
    exit 1
}
if ([string]::IsNullOrEmpty($check)) {
    $imagePath = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\dcos-mesos-slave' -Name ImagePath).ImagePath
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\dcos-mesos-slave' -Name ImagePath -Value "$imagePath --recovery_timeout=1mins"
}

$mesosServiceObjStart = Start-Service dcos-mesos-slave -PassThru
$mesosServiceObjStart.WaitForStatus('Running','00:00:30')
if ($mesosServiceObjStart.Status -ne 'Running') {
    Write-Output "Failed to start the service back up"
    exit 1
} 

$check_after = (sc.exe qc dcos-mesos-slave | Select-String "--recovery_timeout=1mins" | foreach {$_.matches} | select value).Value
if ( $check_after -ne "--recovery_timeout=1mins") {
    Write-Output "Recovery timeout not set to 1min"
    exit 1
}

sc.exe failure dcos-mesos-slave actions= ////// reset= 86400 2>&1 >$null
if ($LastExitCode -ne 0) {
    Write-Output "Unexpected exit code for sc.exe: $LastExitCode. Aborting"
    exit 1
}

taskkill /IM mesos-agent.exe /F 2>&1 >$null
if ($LastExitCode -eq 0) {
    $mesosServiceObj = Get-Service dcos-mesos-slave
    $mesosServiceObj.WaitForStatus('Stopped','00:01:00')
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