Param(
    [Parameter(Mandatory=$false)]
    [string]$GitURL="https://github.com/dcos/spartan",
    [Parameter(Mandatory=$false)]
    [string]$Branch="master",
    [Parameter(Mandatory=$false)]
    [string]$CommitID,
    [Parameter(Mandatory=$false)]
    [string]$ParametersFile="${env:WORKSPACE}\build-parameters.json"
)

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


function Start-SpartanCIProcess {
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
    $stdoutFile = Join-Path $SPARTAN_BUILD_LOGS_DIR $StdoutFileName
    $stderrFile = Join-Path $SPARTAN_BUILD_LOGS_DIR $StderrFileName
    New-Item -ItemType File -Path $stdoutFile
    New-Item -ItemType File -Path $stderrFile
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
        Throw "Failed to get the latest Spartan commit ID. Perhaps it was not yet saved."
    }
    return $global:LATEST_COMMIT_ID
}

function Get-BuildOutputsUrl {
    $spartanCommitID = Get-LatestCommitID
    return "$SPARTAN_BUILD_BASE_URL/$Branch/$spartanCommitID"
}

function Get-BuildLogsUrl {
    $buildOutUrl = Get-BuildOutputsUrl
    return "$buildOutUrl/logs"
}

function Get-RemoteBuildDirectoryPath {
    $spartanCommitID = Get-LatestCommitID
    return "$REMOTE_SPARTAN_BUILD_DIR/$Branch/$spartanCommitID"
}

function Get-RemoteLatestSymlinkPath {
    return "$REMOTE_SPARTAN_BUILD_DIR/$Branch/latest"
}

function Set-LatestSpartanCommit {
    Push-Location $SPARTAN_GIT_REPO_DIR
    try {
        if($CommitID) {
            Start-ExternalCommand { git.exe reset --hard $CommitID } -ErrorMessage "Failed to set the Spartan git repository last commit to: $CommitID."
        }
        Start-ExternalCommand { git.exe log -n 1 } -ErrorMessage "Failed to get the latest commit message for the Spartan git repository" | Out-File "$SPARTAN_BUILD_LOGS_DIR\latest-commit.log"
        $spartanCommitId = Start-ExternalCommand { git.exe log --format="%H" -n 1 } -ErrorMessage "Failed to get the latest commit id for the Spartan git repository"
        Set-Variable -Name "LATEST_COMMIT_ID" -Value $spartanCommitId -Scope Global -Option ReadOnly
    } finally {
        Pop-Location
    }
}

function New-Environment {
    Start-EnvironmentCleanup # Do an environment cleanup to make sure everything is fresh
    New-Directory $SPARTAN_DIR
    New-Directory $SPARTAN_BUILD_OUT_DIR
    New-Directory $SPARTAN_BUILD_LOGS_DIR
    Start-GitClone -URL $GitURL -Branch $Branch -Path $SPARTAN_GIT_REPO_DIR
    # Apply fixes that are not upstream yet
    Push-Location $SPARTAN_GIT_REPO_DIR
    Start-ExternalCommand { git.exe am "$PSScriptRoot\fixes.patch" } -ErrorMessage "Failed to apply local patches"
    Pop-Location
    $global:PARAMETERS["BRANCH"] = $Branch
    Set-LatestSpartanCommit
}

function Start-CommonTests {
    Push-Location $SPARTAN_GIT_REPO_DIR
    Write-Output "Starting the Spartan common tests"
    try {
        Start-SpartanCIProcess -ProcessPath "make.exe" -ArgumentList @("ct") -BuildErrorMessage "Spartan common tests run was not successful" `
                               -StdoutFileName "spartan-common-tests-stdout.log" -StderrFileName "spartan-common-tests-stderr.log"
    } finally {
        Pop-Location
    }
    Write-Output "Successfully finished Spartan common tests run"
}

function Start-EUnitTests {
    Push-Location $SPARTAN_GIT_REPO_DIR
    Write-Output "Starting the Spartan eunit tests"
    try {
        Start-SpartanCIProcess -ProcessPath "make.exe" -ArgumentList @("eunit") -BuildErrorMessage "Spartan eunit tests run was not successful" `
                               -StdoutFileName "spartan-eunit-tests-stdout.log" -StderrFileName "spartan-eunit-tests-stderr.log"
    } finally {
        Pop-Location
    }
    Write-Output "Successfully finished Spartan eunit tests run"
}

function Start-SpartanBuild {
    Push-Location $SPARTAN_GIT_REPO_DIR
    Write-Output "Starting the Spartan build"
    try {
        Start-SpartanCIProcess -ProcessPath "${env:ProgramFiles}\erl8.3\bin\escript.exe" `
                               -StdoutFileName "spartan-make-stdout.log" -StderrFileName "spartan-make-stderr.log" `
                               -ArgumentList @(".\rebar3", "release") -BuildErrorMessage "Spartan failed to build."
    } finally {
        Pop-Location
    }
    Write-Output "Successfully built Spartan"
    $spartanReleaseDir = Join-Path $SPARTAN_BUILD_OUT_DIR "release"
    New-Directory $spartanReleaseDir
    Copy-Item -Recurse "$SPARTAN_GIT_REPO_DIR\_build\default\rel\spartan" "${spartanReleaseDir}\"
    Copy-Item -Recurse "$SPARTAN_GIT_REPO_DIR\_build\default\lib" "${spartanReleaseDir}\"
    Copy-Item -Recurse "$SPARTAN_GIT_REPO_DIR\_build\default\plugins" "${spartanReleaseDir}\"
    $archivePath = Join-Path $SPARTAN_BUILD_OUT_DIR "release.zip"
    Start-ExternalCommand { & 7z.exe a -tzip $archivePath "$spartanReleaseDir\*" -sdel } -ErrorMessage "Failed to compress the Spartan build directory"
    Remove-Item $spartanReleaseDir
}

function Copy-FilesToRemoteServer {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$LocalFilesPath,
        [Parameter(Mandatory=$true)]
        [string]$RemoteFilesPath
    )
    Write-Output "Started copying files from $LocalFilesPath to remote location at ${server}:${RemoteFilesPath}"
    Start-SCPCommand -Server $REMOTE_LOG_SERVER -User $REMOTE_USER -Key $env:SSH_KEY `
                     -LocalPath $LocalFilesPath -RemotePath $RemoteFilesPath
}

function New-RemoteDirectory {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$RemoteDirectoryPath
    )
    $remoteCMD = "if [[ -d $RemoteDirectoryPath ]]; then rm -rf $RemoteDirectoryPath; fi; mkdir -p $RemoteDirectoryPath"
    Start-SSHCommand -Server $REMOTE_LOG_SERVER -User $REMOTE_USER -Key $env:SSH_KEY -Command $remoteCMD
}

function New-RemoteSymlink {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$RemotePath,
        [Parameter(Mandatory=$false)]
        [string]$RemoteSymlinkPath
    )
    $remoteCMD = "if [[ -h $RemoteSymlinkPath ]]; then unlink $RemoteSymlinkPath; fi; ln -s $RemotePath $RemoteSymlinkPath"
    Start-SSHCommand -Server $REMOTE_LOG_SERVER -User $REMOTE_USER -Key $env:SSH_KEY -Command $remoteCMD
}

function Start-LogServerFilesUpload {
    $consoleUrl = "${env:JENKINS_URL}/job/${env:JOB_NAME}/${env:BUILD_NUMBER}/consoleText"
    Start-FileDownload -User ${env:JENKINS_USER} -Password ${env:JENKINS_PASSWORD} `
                       -URL $consoleUrl -Destination "$SPARTAN_BUILD_LOGS_DIR\console-jenkins.log"
    $remoteDirPath = Get-RemoteBuildDirectoryPath
    New-RemoteDirectory -RemoteDirectoryPath $remoteDirPath
    Copy-FilesToRemoteServer "$SPARTAN_BUILD_OUT_DIR\*" $remoteDirPath
    $buildOutputsUrl = Get-BuildOutputsUrl
    $global:PARAMETERS["BUILD_OUTPUTS_URL"] = $buildOutputsUrl
    Write-Output "Build artifacts can be found at: $buildOutputsUrl"
    if($global:PARAMETERS["BUILD_STATUS"] -eq 'PASS') {
        $remoteSymlinkPath = Get-RemoteLatestSymlinkPath
        New-RemoteSymlink -RemotePath $remoteDirPath -RemoteSymlinkPath $remoteSymlinkPath
    }
}

function Start-EnvironmentCleanup {
    # Stop any potential hanging process
    $processNames = @('make', 'erl', 'escript')
    $processNames | Foreach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
    cmd.exe /C "rmdir /s /q $SPARTAN_DIR > nul 2>&1"
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
    New-ParametersFile -FilePath $ParametersFile
    New-Environment
    Start-EUnitTests
    Start-CommonTests
    Start-SpartanBuild
    $global:PARAMETERS["BUILD_STATUS"] = 'PASS'
    $global:PARAMETERS["MESSAGE"] = "Spartan nightly build and testing was successful."
} catch {
    Write-Output $_.ToString()
    Write-Output $_.ScriptStackTrace
    $global:PARAMETERS["BUILD_STATUS"] = 'FAIL'
    $global:PARAMETERS["MESSAGE"] = $_.ToString()
    exit 1
} finally {
    Start-LogServerFilesUpload
    Write-ParametersFile -FilePath $ParametersFile
    Start-EnvironmentCleanup
}
exit 0
