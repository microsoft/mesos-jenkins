Param(
    [Parameter(Mandatory=$false)]
    [string]$GitURL="https://github.com/dcos/dcos-metrics", 
    [Parameter(Mandatory=$false)]
    [string]$Branch="master",
    [Parameter(Mandatory=$false)]
    [string]$CommitID,
    [Parameter(Mandatory=$false)]
    [string]$ParametersFile="${env:WORKSPACE}\build-parameters.json"
)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"

$globalVariables = (Resolve-Path "$PSScriptRoot\..\global-variables.ps1").Path
$ciUtils = (Resolve-Path "$PSScriptRoot\..\Modules\CIUtils").Path

Import-Module $ciUtils
. $globalVariables

$global:PARAMETERS = @{
    "BUILD_STATUS" = $null
    "LOGS_URLS" = @()
    "FAILED_COMMAND" = $null
}
function Install-Prerequisites {
    $prerequisites = @{
        'git'= @{
            'url'= $GIT_URL
            'install_args' = @("/SILENT")
            'install_dir' = $GIT_DIR
        }
        'go'= @{
            'url'= $GOLANG_URL
            'install_args'= @("/quiet")
            'install_dir'= $GOLANG_DIR
        }
        '7zip'= @{
            'url'= $7ZIP_URL
            'install_args'= @("/q")
            'install_dir'= $7ZIP_DIR
        }
    }
    foreach($program in $prerequisites.Keys) {
        if(Test-Path $prerequisites[$program]['install_dir']) {
            Write-Output "$program is already installed"
            continue
        }
        Write-Output "Downloading $program from $($prerequisites[$program]['url'])"
        $fileName = $prerequisites[$program]['url'].Split('/')[-1]
        $programFile = Join-Path $env:TEMP $fileName

        Start-ExecuteWithRetry { Invoke-WebRequest -UseBasicParsing -Uri $prerequisites[$program]['url'] -OutFile $programFile}
        $parameters = @{
            'FilePath' = $programFile
            'ArgumentList' = $prerequisites[$program]['install_args']
            'Wait' = $true
            'PassThru' = $true
        }
        if($programFile.EndsWith('.msi')) {
            $parameters['FilePath'] = 'msiexec.exe'
            $parameters['ArgumentList'] += @("/i", $programFile)
        }
        Write-Output "Installing $programFile"
        $p = Start-Process @parameters
        if($p.ExitCode -ne 0) {
            Throw "Failed to install prerequisite $programFile during the environment setup : $($p.ExitCode)"
        }
    }
    # Add all the tools to PATH
    $toolsDirs = @("$GOLANG_DIR\bin", "$GIT_DIR\cmd", "$GIT_DIR\bin", "$7ZIP_DIR")
    $env:PATH += ';' + ($toolsDirs -join ';')
}

function Start-MetricsCIProcess {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$ProcessPath,
        [Parameter(Mandatory=$false)]
        [string[]]$ArgumentList,
        [Parameter(Mandatory=$true)]
        [string]$StdoutFileName,
        [Parameter(Mandatory=$true)]
        [string]$StderrFileName,
        [Parameter(Mandatory=$true)]
        [string]$BuildErrorMessage
    )
    $stdoutFile = Join-Path $METRICS_BUILD_LOGS_DIR $StdoutFileName
    $stderrFile = Join-Path $METRICS_BUILD_LOGS_DIR $StderrFileName
    New-Item -ItemType File -Path $stdoutFile -Force
    New-Item -ItemType File -Path $stderrFile -Force
    $logsUrl = Get-BuildLogsUrl
    $stdoutUrl = "${logsUrl}/${StdoutFileName}"
    $stderrUrl = "${logsUrl}/${StderrFileName}"
    $command = $ProcessPath -replace '\\', '\\'
    if($ArgumentList.Count) {
        $ArgumentList | Foreach-Object { $command += " $($_ -replace '\\', '\\')" }
    }
    try {
        Wait-ProcessToFinish -ProcessPath $ProcessPath -ArgumentList $ArgumentList `
                             -StandardOutput $stdoutFile -StandardError $stderrFile
        $msg = "Successfully executed: $command"
    } catch {
        $msg = "Failed command: $command"
        $global:PARAMETERS["BUILD_STATUS"] = 'FAIL'
        $global:PARAMETERS["LOGS_URLS"] += $($stdoutUrl, $stderrUrl)
        $global:PARAMETERS["FAILED_COMMAND"] = $command
        Write-Output "Exception: $($_.ToString())"
        Throw $BuildErrorMessage
    } finally {
        Write-Output $msg
        Write-Output "Stdout log available at: $stdoutUrl"
        Write-Output "Stderr log available at: $stderrUrl"
    }
}

function Get-LatestCommitID {
    if(!$global:LATEST_COMMIT_ID) {
        Throw "Failed to get the latest dcos-metrics commit ID. Perhaps it has not saved."
    }
    return $global:LATEST_COMMIT_ID
}

function Set-LatestMetricsCommit {
    Push-Location $METRICS_GIT_REPO_DIR
    try {
        if($CommitID) {
            Start-ExternalCommand { git.exe reset --hard $CommitID } -ErrorMessage "Failed to set Metrics git repo last commit to: $CommitID."
        }
        Start-ExternalCommand { git.exe log -n 1 } -ErrorMessage "Failed to get the latest commit message for the Metrics git repo" | Out-File "$METRICS_BUILD_LOGS_DIR\latest-commit.log"
        $commitId = Start-ExternalCommand { git.exe log --format="%H" -n 1 } -ErrorMessage "Failed to get the latest commit id for the dcos-metrics git repo"
        Set-Variable -Name "LATEST_COMMIT_ID" -Value $commitId -Scope Global
    } finally {
        Pop-Location
    }
}

function New-TestingEnvironment {
    Write-Output "Creating new tests environment"
    Start-EnvironmentCleanup # Do an environment cleanup to make sure everything is fresh
    New-Directory $METRICS_DIR
    New-Directory $METRICS_BUILD_OUT_DIR -RemoveExisting
    New-Directory $METRICS_BUILD_LOGS_DIR
    $global:PARAMETERS["BRANCH"] = $Branch
    Start-GitClone -Path $METRICS_GIT_REPO_DIR -URL $GitURL -Branch $Branch
    Set-LatestMetricsCommit
    $env:GOPATH = $METRICS_DIR
    $goBinPath = Join-Path $GOLANG_DIR "bin"
    [System.Environment]::SetEnvironmentVariable('GOBIN', $goBinPath)
    Write-Output "New tests environment was successfully created"
}

function Start-DCOSMetricsBuild {
    Write-Output "Building DC/OS Metrics in $METRICS_GIT_REPO_DIR"
    Push-Location $METRICS_GIT_REPO_DIR
    try {
        New-Item -ItemType directory -Path ".\build" -Force
        Start-MetricsCIProcess  -ProcessPath "powershell.exe" `
                                    -StdoutFileName "metrics-build-stdout.log" `
                                    -StderrFileName "metrics-build-stderr.log" `
                                    -ArgumentList @(".\scripts\build.ps1", "collector") `
                                    -BuildErrorMessage "Metrics failed to build."
        Start-ExternalCommand { & go.exe get .\... } -ErrorMessage "Failed to setup the dependent packages"
        Copy-Item -Path "$METRICS_GIT_REPO_DIR\build\collector\dcos-metrics-collector-*" -Destination "$METRICS_GIT_REPO_DIR/dcos-metrics.exe"
    } finally {
        Pop-Location
    }
    Write-Output "DC/OS Metrics was successfully built"
}

function New-DCOSMetricsPackage {
    Write-Output "Creating DC/OS Metrics package"
    Write-Output "METRICS_GIT_REPO_DIR: $METRICS_GIT_REPO_DIR"
    New-Directory $METRICS_BUILD_BINARIES_DIR
    $MetricsClusterIdFile = Join-Path $METRICS_BUILD_BINARIES_DIR "cluster-id"
    Write-Output "Creating cluster-id file: $MetricsClusterIdFile"
    # The following cluster-id file was created for setting up a dcosInfo's default
    # clusterIDLocation. It will be overwritten by the real cluster id in the real 
    # scenarios, which always set it. It looks like any guid is good that because
    # this guid was not acually used, I copied the current this hardcoded guid from
    # the dcos-go repo.
    $clusterid = "{fdb1d7c0-06cf-4d65-bb9b-a8920bb854ef}"
    $clusterid | Set-Content $MetricsClusterIdFile
    Copy-Item -Path "$PSScriptRoot\utils\detect_ip.ps1" -Destination $METRICS_BUILD_BINARIES_DIR
    Copy-Item -Force -Path "$METRICS_GIT_REPO_DIR\*.exe" -Destination "$METRICS_BUILD_BINARIES_DIR\"
    Copy-Item -Recurse -Path "$PSScriptRoot\config" -Destination "$METRICS_BUILD_BINARIES_DIR\config"
    Compress-Files -FilesDirectory "$METRICS_BUILD_BINARIES_DIR\" -Filter "*.*" -Archive "$METRICS_BUILD_BINARIES_DIR\metrics.zip"
    Write-Output "DC/OS Metrics package was successfully generated at $METRICS_BUILD_BINARIES_DIR\metrics.zip"
}

function Copy-FilesToRemoteServer {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$LocalFilesPath,
        [Parameter(Mandatory=$true)]
        [string]$RemoteFilesPath
    )
    Write-Output "Started copying files from $LocalFilesPath to remote location at ${server}:${RemoteFilesPath}"
    Start-SCPCommand -Server $STORAGE_SERVER_ADDRESS -User $STORAGE_SERVER_USER -Key $env:SSH_KEY `
                     -LocalPath $LocalFilesPath -RemotePath $RemoteFilesPath
}

function New-RemoteDirectory {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$RemoteDirectoryPath
    )
    $remoteCMD = "if [[ -d $RemoteDirectoryPath ]]; then rm -rf $RemoteDirectoryPath; fi; mkdir -p $RemoteDirectoryPath"
    Start-SSHCommand -Server $STORAGE_SERVER_ADDRESS -User $STORAGE_SERVER_USER -Key $env:SSH_KEY -Command $remoteCMD
}

function New-RemoteSymlink {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$RemotePath,
        [Parameter(Mandatory=$false)]
        [string]$RemoteSymlinkPath
    )
    $remoteCMD = "if [[ -h $RemoteSymlinkPath ]]; then unlink $RemoteSymlinkPath; fi; ln -s $RemotePath $RemoteSymlinkPath"
    Start-SSHCommand -Server $STORAGE_SERVER_ADDRESS -User $STORAGE_SERVER_USER -Key $env:SSH_KEY -Command $remoteCMD
}

function Get-MetricsBuildRelativePath {
    $repositoryName = $GitURL.Split("/")[-1]
    $metricsCommitID = Get-LatestCommitID
    return "${repositoryName}-${Branch}-${metricsCommitID}"
}

function Get-RemoteBuildDirectoryPath {
    $relativePath = Get-MetricsBuildRelativePath
    return "$ARTIFACTS_DIRECTORY/${env:JOB_NAME}/${env:BUILD_ID}/$relativePath"
}

function Get-BuildOutputsUrl {
    $relativePath = Get-MetricsBuildRelativePath
    return "$ARTIFACTS_BASE_URL/${env:JOB_NAME}/${env:BUILD_ID}/$relativePath"
}

function Get-BuildLogsUrl {
    $buildOutUrl = Get-BuildOutputsUrl
    return "$buildOutUrl/logs"
}

function Get-BuildBinariesUrl {
    $buildOutUrl = Get-BuildOutputsUrl
    return "$buildOutUrl/binaries"
}

function New-RemoteLatestSymlinks {
    $remoteDirPath = Get-RemoteBuildDirectoryPath
    $latestPath = "${ARTIFACTS_DIRECTORY}/${env:JOB_NAME}/latest-metrics-build"
    New-RemoteSymlink -RemotePath $remoteDirPath -RemoteSymlinkPath $latestPath
}

function Start-LogServerFilesUpload {
    $consoleUrl = "${env:JENKINS_URL}/job/${env:JOB_NAME}/${env:BUILD_NUMBER}/consoleText"
    Start-FileDownload -User ${env:JENKINS_USER} -Password ${env:JENKINS_PASSWORD} `
                       -URL $consoleUrl -Destination "$METRICS_BUILD_LOGS_DIR\console-jenkins.log"
    $remoteDirPath = Get-RemoteBuildDirectoryPath
    New-RemoteDirectory -RemoteDirectoryPath $remoteDirPath
    Copy-FilesToRemoteServer "$METRICS_BUILD_OUT_DIR\*" $remoteDirPath
    $buildOutputsUrl = Get-BuildOutputsUrl
    $global:PARAMETERS["BUILD_OUTPUTS_URL"] = $buildOutputsUrl
    Write-Output "Build artifacts can be found at: $buildOutputsUrl"
    if($global:PARAMETERS["BUILD_STATUS"] -eq "PASS") {
        New-RemoteLatestSymlinks
    }
 }

function Start-EnvironmentCleanup {
    # Stop any potential hanging process
    $processes = @('go')
    $processes | Foreach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
    cmd.exe /C "rmdir /s /q $METRICS_DIR > nul 2>&1"
}

function Get-SuccessBuildMessage {
    return "Successful DC/OS Metrics Windows build and testing for repository $GitURL on $Branch branch"
}

function Start-TempDirCleanup {
    Get-ChildItem $env:TEMP | Where-Object {
        $_.Name -notmatch "^jna\-[0-9]*$|^hsperfdata.*_Metrics$"
    } | ForEach-Object {
        $fullPath = $_.FullName
        if($_.FullName -is [System.IO.DirectoryInfo]) {
            cmd.exe /C "rmdir /s /q ${fullPath} > nul 2>&1"
        } else {
            cmd.exe /C "del /Q /S /F ${fullPath} > nul 2>&1"
        }
    }
}

function Start-DCOSMetricsUnitTests {
    Write-Output "Run DC/OS Metrics unit tests"
    Push-Location $METRICS_GIT_REPO_DIR
    try {
        Start-MetricsCIProcess  -ProcessPath "powershell.exe" `
                                    -StdoutFileName "metrics-unitests-stdout.log" `
                                    -StderrFileName "metrics-unitests-stderr.log" `
                                    -ArgumentList @(".\scripts\test.ps1", "collector unit") `
                                    -BuildErrorMessage "Metrics unittests failed."
    } finally {
        Pop-Location
    }
    Write-Output "DC/OS Metrics unit tests passed"
}

function New-ParametersFile {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    if(Test-Path $FilePath) {
        Remove-Item -Force $FilePath
    }
    New-Item -ItemType File -Path $FilePath | Out-Null
}

function Write-ParametersFile {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    if($global:PARAMETERS["LOGS_URLS"]) {
        $global:PARAMETERS["LOGS_URLS"] = $global:PARAMETERS["LOGS_URLS"] -join '|'
    }
    $json = ConvertTo-Json -InputObject $global:PARAMETERS
    Set-Content -Path $FilePath -Value $json
}

try {
    Start-TempDirCleanup
    New-ParametersFile -FilePath $ParametersFile
    Install-Prerequisites
    New-TestingEnvironment
    Start-DCOSMetricsBuild

    <# To avoid the followign three test failures only seen when run with GO 1.10,
       GO 1.94 is used specifically for getting a clean unittest run.
       dcos-metrics/plugins/datadog-standalone/datadog-standalone_test.go:111: Fatalf format %s has 
              arg uptime.Host of wrong type *string
       dcos-metrics/plugins/statsd/statsd.go:130: Errorf format %q has arg v of wrong type float64
       FAIL: TestGetNewConfig (2.19s)
    #>
    Start-DCOSMetricsUnitTests
    New-DCOSMetricsPackage
    $global:PARAMETERS["BUILD_STATUS"] = "PASS"
    $global:PARAMETERS["MESSAGE"] = Get-SuccessBuildMessage
} catch {
    Write-Output $_.ToString()
    Write-Output $_.ScriptStackTrace
    $global:PARAMETERS["BUILD_STATUS"] = "FAIL"
    $global:PARAMETERS["MESSAGE"] = $_.ToString()
    exit 1
} finally {
    Start-LogServerFilesUpload
    Write-ParametersFile -FilePath $ParametersFile
    Start-EnvironmentCleanup
}
exit 0
