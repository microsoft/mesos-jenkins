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
$timeout = New-TimeSpan -Seconds 30
$mesosServiceObj = Stop-Service $mesosServiceName -PassThru
$mesosServiceObj.WaitForStatus('Stopped',$timeout)
if ($mesosServiceObj.Status -ne 'Stopped') { 
    Write-Output "FAILURE"
} else {
    Write-Output "SUCCESS"
}