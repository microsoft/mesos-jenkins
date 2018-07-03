$mesosServiceObj = Start-Service dcos-mesos-slave -PassThru
$mesosServiceObj.WaitForStatus('Running','00:00:30')
if ($mesosServiceObj.Status -ne 'Running') {
    Write-Output "FAILURE"
} else {
    Write-Output "SUCCESS"
}