$ErrorActionPreference = 'Stop'

$consoleLogFile = Join-Path $env:WORKSPACE "spartan-build-${env:BRANCH}-${env:BUILD_NUMBER}.log"
$windowsBuildScript = (Resolve-Path "$PSScriptRoot\..\start-windows-build.ps1").Path
& "$windowsBuildScript" -Branch $env:BRANCH -CommitID $env:COMMIT_ID | Tee-Object -FilePath $consoleLogFile
$exitCode = $LASTEXITCODE
Remove-Item -Force -ErrorAction SilentlyContinue -Path $consoleLogFile
exit $exitCode
