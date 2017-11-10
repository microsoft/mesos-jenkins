$ErrorActionPreference = 'Stop'

$paramsFile = Join-Path $env:WORKSPACE "mesos-build-parameters.txt"
$consoleLogFile = Join-Path $env:WORKSPACE "mesos-build-${env:BRANCH}-${env:BUILD_NUMBER}.log"
$windowsBuildScript = (Resolve-Path "$PSScriptRoot\..\start-windows-build.ps1").Path
& "$windowsBuildScript" -Branch $env:BRANCH -CommitID $env:COMMIT_ID -ParametersFile $paramsFile | Tee-Object -FilePath $consoleLogFile
$exitCode = $LASTEXITCODE
Remove-Item -Force -ErrorAction SilentlyContinue -Path $consoleLogFile
exit $exitCode
