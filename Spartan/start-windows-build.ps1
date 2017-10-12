Param(
    [Parameter(Mandatory=$false)]
    [string]$Branch="master",
    [Parameter(Mandatory=$false)]
    [string]$CommitID
)

$ErrorActionPreference = "Stop"

$globalVariables = (Resolve-Path "$PSScriptRoot\..\global-variables.ps1").Path
$ciUtils = (Resolve-Path "$PSScriptRoot\..\Modules\CIUtils").Path

Import-Module $ciUtils
. $globalVariables

$global:BUILD_STATUS = $null


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
        $global:BUILD_STATUS = 'FAIL'
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
    Start-GitClone -URL $SPARTAN_GIT_URL -Branch $Branch -Path $SPARTAN_GIT_REPO_DIR
    Set-LatestSpartanCommit
    Start-ExternalCommand { git.exe config --global user.email "ostcauto@microsoft.com" } -ErrorMessage "Failed to set git user email"
    Start-ExternalCommand { git.exe config --global user.name "ostcauto" } -ErrorMessage "Failed to set git user name"
}

function Start-SpartanBuild {
    Push-Location $SPARTAN_GIT_REPO_DIR
    Write-Output "Starting the Spartan build"
    try {
        Start-SpartanCIProcess -ProcessPath "make.exe" -StdoutFileName "spartan-build-make-stdout.log" -StderrFileName "spartan-build-make-stderr.log" `
                               -ArgumentList @("rel") -BuildErrorMessage "Spartan failed to build."
    } finally {
        Pop-Location
    }
    Write-Output "Successfully built Spartan"
    $spartanBuildDir = Join-Path $SPARTAN_BUILD_OUT_DIR "spartan-build"
    Copy-Item -Recurse "$SPARTAN_GIT_REPO_DIR\_build\prod\rel\spartan" $spartanBuildDir
    $archivePath = Join-Path $SPARTAN_BUILD_OUT_DIR "spartan-build.zip"
    Start-ExternalCommand { & 7z.exe a -tzip $archivePath "$spartanBuildDir\*" -sdel } -ErrorMessage "Failed to compress the Spartan build directory"
}

function Copy-FilesToRemoteServer {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$LocalFilesPath,
        [Parameter(Mandatory=$true)]
        [string]$RemoteFilesPath
    )
    Write-Output "Started copying files from $LocalFilesPath to remote location at ${server}:${RemoteFilesPath}"
    Start-SCPCommand -Server $REMOTE_LOG_SERVER -User $REMOTE_USER -Key $REMOTE_KEY `
                     -LocalPath $LocalFilesPath -RemotePath $RemoteFilesPath
}

function New-RemoteDirectory {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$RemoteDirectoryPath
    )
    $remoteCMD = "if [[ -d $RemoteDirectoryPath ]]; then rm -rf $RemoteDirectoryPath; fi; mkdir -p $RemoteDirectoryPath"
    Start-SSHCommand -Server $REMOTE_LOG_SERVER -User $REMOTE_USER -Key $REMOTE_KEY -Command $remoteCMD
}

function New-RemoteSymlink {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$RemotePath,
        [Parameter(Mandatory=$false)]
        [string]$RemoteSymlinkPath
    )
    $remoteCMD = "if [[ -h $RemoteSymlinkPath ]]; then unlink $RemoteSymlinkPath; fi; ln -s $RemotePath $RemoteSymlinkPath"
    Start-SSHCommand -Server $REMOTE_LOG_SERVER -User $REMOTE_USER -Key $REMOTE_KEY -Command $remoteCMD
}

function Start-LogServerFilesUpload {
    Param(
        [Parameter(Mandatory=$false)]
        [switch]$NewLatest
    )
    $consoleLog = Join-Path $env:WORKSPACE "spartan-build-$Branch-${env:BUILD_NUMBER}.log"
    if(Test-Path $consoleLog) {
        Copy-Item -Force $consoleLog "$SPARTAN_BUILD_LOGS_DIR\jenkins-console.log"
    }
    $remoteDirPath = Get-RemoteBuildDirectoryPath
    New-RemoteDirectory -RemoteDirectoryPath $remoteDirPath
    Copy-FilesToRemoteServer "$SPARTAN_BUILD_OUT_DIR\*" $remoteDirPath
    $buildOutputsUrl = Get-BuildOutputsUrl
    Write-Output "Build artifacts can be found at: $buildOutputsUrl"
    if($NewLatest) {
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


try {
    New-Environment
    Start-SpartanBuild
    $global:BUILD_STATUS = 'PASS'
} catch {
    Write-Output $_.ToString()
    $global:BUILD_STATUS = 'FAIL'
    exit 1
} finally {
    if($global:BUILD_STATUS -eq 'PASS') {
        Start-LogServerFilesUpload -NewLatest
    } else {
        Start-LogServerFilesUpload
    }
    Start-EnvironmentCleanup
}
exit 0
