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

$mesosServiceObj = Start-Service $mesosServiceName -PassThru
$timeout = New-TimeSpan -Seconds 60
$mesosServiceObj.WaitForStatus('Running',$timeout)
if ($mesosServiceObj.Status -ne 'Running') {
    Write-Output "FAILURE"
} else {
    Write-Output "SUCCESS"
}
