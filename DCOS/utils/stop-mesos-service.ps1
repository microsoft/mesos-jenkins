$mesosServiceObj = Stop-Service dcos-mesos-slave -PassThru
$mesosServiceObj.WaitForStatus('Stopped','00:00:30')
if ($mesosServiceObj.Status -ne 'Stopped') { 
    Write-Output "FAILURE"
} else {
    Write-Output "SUCCESS"
}