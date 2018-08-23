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
$timeout_30s = New-TimeSpan -Seconds 30
$mesosServiceObj = Stop-Service $mesosServiceName -PassThru
$mesosServiceObj.WaitForStatus('Stopped',$timeout_30s)
if ($mesosServiceObj.Status -ne 'Stopped') {
    Write-Output "Failed to stop the service"
    exit 1
}

$check = sc.exe qc $mesosServiceName | Select-String "--recovery_timeout=1mins"
if ($LastExitCode -ne 0) {
    Write-Output "Unexpected exit code for sc.exe: $LastExitCode. Aborting"
    exit 1
}
if ([string]::IsNullOrEmpty($check)) {
    $imagePath = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$mesosServiceName" -Name ImagePath).ImagePath
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$mesosServiceName" -Name ImagePath -Value "$imagePath --recovery_timeout=1mins"
}

$mesosServiceObjStart = Start-Service $mesosServiceName -PassThru
$mesosServiceObjStart.WaitForStatus('Running',$timeout_30s)
if ($mesosServiceObjStart.Status -ne 'Running') {
    Write-Output "Failed to start the service back up"
    exit 1
} 

$check_after = (sc.exe qc $mesosServiceName | Select-String "--recovery_timeout=1mins" | foreach {$_.matches} | select value).Value
if ( $check_after -ne "--recovery_timeout=1mins") {
    Write-Output "Recovery timeout not set to 1min"
    exit 1
}

sc.exe failure $mesosServiceName actions= ////// reset= 86400 2>&1 >$null
if ($LastExitCode -ne 0) {
    Write-Output "Unexpected exit code for sc.exe: $LastExitCode. Aborting"
    exit 1
}

$timeout_1min = New-TimeSpan -Minutes 1
taskkill /IM mesos-agent.exe /F 2>&1 >$null
if ($LastExitCode -eq 0) {
    $mesosServiceObj = Get-Service $mesosServiceName
    $mesosServiceObj.WaitForStatus('Stopped',$timeout_1min)
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