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

$mesosServiceObj = Start-Service $mesosServiceName -PassThru
$mesosServiceObj.WaitForStatus('Running','00:00:30')
if ($mesosServiceObj.Status -ne 'Running') {
    Write-Output "FAILURE"
} else {
    Write-Output "SUCCESS"
}