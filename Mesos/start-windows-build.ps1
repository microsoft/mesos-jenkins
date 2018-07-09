Param(
    [Parameter(Mandatory=$false)]
    [string]$GitURL="https://github.com/apache/mesos",
    [Parameter(Mandatory=$false)]
    [string]$ReviewID,
    [Parameter(Mandatory=$false)]
    [string]$Branch="master",
    [Parameter(Mandatory=$false)]
    [string]$CommitID,
    [Parameter(Mandatory=$false)]
    [string]$ParametersFile="${env:WORKSPACE}\build-parameters.json",
    [Parameter(Mandatory=$false)]
    [switch]$EnableSSL
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


function Start-MesosCIProcess {
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
    $stdoutFile = Join-Path $MESOS_BUILD_LOGS_DIR $StdoutFileName
    $stderrFile = Join-Path $MESOS_BUILD_LOGS_DIR $StderrFileName
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

function Add-ReviewBoardPatch {
    Write-Output "Applying Reviewboard patch(es) over Mesos $Branch branch"
    $tempFile = Join-Path $env:TEMP "mesos_dependent_review_ids"
    Start-MesosCIProcess -ProcessPath "python.exe" -StdoutFileName "get-review-ids-stdout.log" -StderrFileName "get-review-ids-stderr.log" `
                         -ArgumentList @("$PSScriptRoot\utils\get-review-ids.py", "-r", $ReviewID, "-o", $tempFile) `
                         -BuildErrorMessage "Failed to get dependent review IDs for the current patch."
    $reviewIDs = Get-Content $tempFile
    if(!$reviewIDs) {
        Write-Output "There aren't any reviews to be applied"
        return
    }
    Write-Output "Patches IDs that need to be applied: $reviewIDs"
    foreach($id in $reviewIDs) {
        Write-Output "Applying patch ID: $id"
        Push-Location $MESOS_GIT_REPO_DIR
        try {
            if($id -eq $ReviewID) {
                $buildErrorMsg = "Failed to apply the current review."
            } else {
                $buildErrorMsg = "Failed to apply the dependent review: $id."
            }
            # TODO(andschwa): Move this back to `support\apply-reviews.py` after the Python 2 deprecation is complete.
            Start-MesosCIProcess -ProcessPath "python.exe" -StdoutFileName "apply-review-${id}-stdout.log" -StderrFileName "apply-review-${id}-stderr.log" `
                                 -ArgumentList @(".\support\python3\apply-reviews.py", "-n", "-r", $id) -BuildErrorMessage $buildErrorMsg
        } finally {
            Pop-Location
        }
    }
    $global:PARAMETERS["APPLIED_REVIEWS"] = $reviewIDs -join '|'
    Write-Output "Finished applying Reviewboard patch(es)"
}

function Set-LatestMesosCommit {
    Push-Location $MESOS_GIT_REPO_DIR
    try {
        if($CommitID) {
            Start-ExternalCommand { git.exe reset --hard $CommitID } -ErrorMessage "Failed to set Mesos git repo last commit to: $CommitID."
        }
        Start-ExternalCommand { git.exe log -n 1 } -ErrorMessage "Failed to get the latest commit message for the Mesos git repo" | Out-File "$MESOS_BUILD_LOGS_DIR\latest-commit.log"
        $mesosCommitId = Start-ExternalCommand { git.exe log --format="%H" -n 1 } -ErrorMessage "Failed to get the latest commit id for the Mesos git repo"
        Set-Variable -Name "LATEST_COMMIT_ID" -Value $mesosCommitId -Scope Global -Option ReadOnly
    } finally {
        Pop-Location
    }
}

function Get-LatestCommitID {
    if(!$global:LATEST_COMMIT_ID) {
        Throw "Failed to get the latest Mesos commit ID. Perhaps it has not saved."
    }
    return $global:LATEST_COMMIT_ID
}

function New-Environment {
    Write-Output "Creating new tests environment"
    Start-EnvironmentCleanup # Do an environment cleanup to make sure everything is fresh
    New-Directory $MESOS_DIR
    New-Directory $MESOS_BUILD_OUT_DIR -RemoveExisting
    New-Directory $MESOS_BUILD_LOGS_DIR
    $global:PARAMETERS["BRANCH"] = $Branch
    # Clone Mesos repository
    Start-GitClone -Path $MESOS_GIT_REPO_DIR -URL $GitURL -Branch $Branch
    Set-LatestMesosCommit
    if($ReviewID) {
        Write-Output "Started testing review: https://reviews.apache.org/r/${ReviewID}"
        # Pull the patch and all the dependent ones, if a review ID was given
        Add-ReviewBoardPatch
    }
    Set-VCVariables "15.0"
    Write-Output "New tests environment was successfully created"
}

function Start-MesosBuild {
    Write-Output "Building Mesos"
    Push-Location $MESOS_DIR
    $logsUrl = Get-BuildLogsUrl
    try {
        $generatorName = "Visual Studio 15 2017 Win64"
        $parameters = @("$MESOS_GIT_REPO_DIR", "-G", "`"$generatorName`"", "-T", "host=x64", "-DHAS_AUTHENTICATION=ON", "-DENABLE_JAVA=ON")
        if($EnableSSL) {
            $parameters += @("-DENABLE_LIBEVENT=ON", "-DENABLE_SSL=ON")
        } else {
            $parameters += "-DENABLE_LIBWINIO=ON"
        }
        Start-MesosCIProcess -ProcessPath "cmake.exe" -StdoutFileName "mesos-cmake-stdout.log" -StderrFileName "mesos-cmake-stderr.log" `
                             -ArgumentList $parameters -BuildErrorMessage "Mesos failed to build."
    } finally {
        Pop-Location
    }
    Write-Output "Mesos was successfully built"
}

function Start-StoutTestsBuild {
    Write-Output "Started Mesos stout-tests build"
    Push-Location $MESOS_DIR
    try {
        Start-MesosCIProcess -ProcessPath "cmake.exe" -StdoutFileName "stout-tests-cmake-stdout.log" -StderrFileName "stout-tests-cmake-stderr.log" `
                             -ArgumentList @("--build", ".", "--target", "stout-tests", "--config", "Debug", "-- /maxcpucount") `
                             -BuildErrorMessage "Mesos stout-tests failed to build."
    } finally {
        Pop-Location
    }
    Write-Output "stout-tests were successfully built"
}

function Start-StdoutTestsRun {
    Write-Output "Started Mesos stout-tests run"
    Start-MesosCIProcess -ProcessPath "$MESOS_DIR\3rdparty\stout\tests\Debug\stout-tests.exe" `
                         -StdoutFileName "stout-tests-stdout.log" -StderrFileName "stout-tests-stderr.log" `
                         -BuildErrorMessage "Some Mesos stout-tests tests failed."
    Write-Output "stout-tests PASSED"
}

function Start-LibprocessTestsBuild {
    Write-Output "Started Mesos libprocess-tests build"
    Push-Location $MESOS_DIR
    try {
        Start-MesosCIProcess -ProcessPath "cmake.exe" -StdoutFileName "libprocess-tests-cmake-stdout.log" -StderrFileName "libprocess-tests-cmake-stderr.log" `
                             -ArgumentList @("--build", ".", "--target", "libprocess-tests", "--config", "Debug", "-- /maxcpucount") `
                             -BuildErrorMessage "Mesos libprocess-tests failed to build"
    } finally {
        Pop-Location
    }
    Write-Output "libprocess-tests were successfully built"
}

function Start-LibprocessTestsRun {
    Write-Output "Started Mesos libprocess-tests run"
    Start-MesosCIProcess -ProcessPath "$MESOS_DIR\3rdparty\libprocess\src\tests\Debug\libprocess-tests.exe" `
                         -StdoutFileName "libprocess-tests-stdout.log" -StderrFileName "libprocess-tests-stderr.log" `
                         -BuildErrorMessage "Some Mesos libprocess-tests failed."
    Write-Output "libprocess-tests PASSED"
}

function Start-MesosTestsBuild {
    Write-Output "Started Mesos tests build"
    Push-Location $MESOS_DIR
    try {
        Start-MesosCIProcess -ProcessPath "cmake.exe" -StdoutFileName "mesos-tests-cmake-stdout.log" -StderrFileName "mesos-tests-cmake-stderr.log" `
                             -ArgumentList @("--build", ".", "--target", "mesos-tests", "--config", "Debug", "-- /maxcpucount") `
                             -BuildErrorMessage "Mesos tests failed to build."
    } finally {
        Pop-Location
    }
    Write-Output "Mesos tests were successfully built"
}

function Start-MesosTestsRun {
    Write-Output "Started Mesos tests run"
    Start-MesosCIProcess -ProcessPath "$MESOS_DIR\src\mesos-tests.exe" -ArgumentList @('--verbose') `
                         -StdoutFileName "mesos-tests-stdout.log" -StderrFileName "mesos-tests-stderr.log" `
                         -BuildErrorMessage "Some Mesos tests failed."
    Write-Output "mesos-tests PASSED"
}

function New-MesosBinaries {
    Write-Output "Started building Mesos binaries"
    Push-Location $MESOS_DIR
    try {
        Start-MesosCIProcess -ProcessPath "cmake.exe" -StdoutFileName "mesos-binaries-cmake-stdout.log" -StderrFileName "mesos-binaries-cmake-stderr.log" `
                             -ArgumentList @("--build", ".", "--config", "Release", "-- /maxcpucount") -BuildErrorMessage "Mesos binaries failed to build."
    } finally {
        Pop-Location
    }
    Write-Output "Mesos binaries were successfully built"
    New-Directory $MESOS_BUILD_BINARIES_DIR
    Copy-Item -Force -Exclude @("mesos-master.exe", "mesos-tests.exe", "test-helper.exe") -Path "$MESOS_DIR\src\*.exe" -Destination "$MESOS_BUILD_BINARIES_DIR\"
    Compress-Files -FilesDirectory "$MESOS_BUILD_BINARIES_DIR\" -Filter "*.exe" -Archive "$MESOS_BUILD_BINARIES_DIR\mesos-binaries.zip"
    Copy-Item -Force -Exclude @("mesos-master.pdb", "mesos-tests.pdb", "test-helper.pdb") -Path "$MESOS_DIR\src\*.pdb" -Destination "$MESOS_BUILD_BINARIES_DIR\"
    Compress-Files -FilesDirectory "$MESOS_BUILD_BINARIES_DIR\" -Filter "*.pdb" -Archive "$MESOS_BUILD_BINARIES_DIR\mesos-pdb.zip"
    Write-Output "Mesos binaries were successfully generated"
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

function Get-MesosBuildRelativePath {
    $repositoryName = $GitURL.Split("/")[-1]
    if($ReviewID) {
        return "${repositoryName}-review-${ReviewID}"
    }
    $mesosCommitID = Get-LatestCommitID
    return "${repositoryName}-${Branch}-${mesosCommitID}"
}

function Get-RemoteBuildDirectoryPath {
    $relativePath = Get-MesosBuildRelativePath
    return "$ARTIFACTS_DIRECTORY/${env:JOB_NAME}/${env:BUILD_ID}/$relativePath"
}

function Get-BuildOutputsUrl {
    $relativePath = Get-MesosBuildRelativePath
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
    $latestPath = "${ARTIFACTS_DIRECTORY}/${env:JOB_NAME}/latest-mesos-build"
    New-RemoteSymlink -RemotePath $remoteDirPath -RemoteSymlinkPath $latestPath
}

function Start-LogServerFilesUpload {
    $consoleUrl = "${env:JENKINS_URL}/job/${env:JOB_NAME}/${env:BUILD_NUMBER}/consoleText"
    Start-FileDownload -User ${env:JENKINS_USER} -Password ${env:JENKINS_PASSWORD} `
                       -URL $consoleUrl -Destination "$MESOS_BUILD_LOGS_DIR\console-jenkins.log"
    $remoteDirPath = Get-RemoteBuildDirectoryPath
    New-RemoteDirectory -RemoteDirectoryPath $remoteDirPath
    ###
    ### NOTE(ibalutoiu): We copy the build outputs to a temporary location before
    ###                  doing the SCP to the storage server due to a bug in Jenkins
    ###                  sometimes leading to leaked file descriptors.
    ###
    $tempDir = Join-Path $env:TEMP "build-output"
    if(Test-Path $tempDir) {
        Remove-Item -Recurse -Force $tempDir
    }
    Copy-Item -Recurse -Force $MESOS_BUILD_OUT_DIR $tempDir
    Copy-FilesToRemoteServer "${tempDir}\*" $remoteDirPath
    ###
    Remove-Item -Recurse -Force $tempDir
    $buildOutputsUrl = Get-BuildOutputsUrl
    $global:PARAMETERS["BUILD_OUTPUTS_URL"] = $buildOutputsUrl
    Write-Output "Build artifacts can be found at: $buildOutputsUrl"
    if($global:PARAMETERS["BUILD_STATUS"] -eq "PASS") {
        New-RemoteLatestSymlinks
    }
}

function Start-EnvironmentCleanup {
    # Stop any potential hanging process
    $processes = @('python', 'git', 'cl', 'cmake',
                   'stout-tests', 'libprocess-tests', 'mesos-tests')
    $processes | Foreach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
    cmd.exe /C "rmdir /s /q $MESOS_DIR > nul 2>&1"
}

function Get-SuccessBuildMessage {
    if($ReviewID) {
        return "Mesos patch $ReviewID was successfully built and tested."
    }
    return "Successful Mesos nightly build and testing for repository $GitURL on branch $Branch"
}

function Start-TempDirCleanup {
    Get-ChildItem $env:TEMP | Where-Object {
        $_.Name -notmatch "^jna\-[0-9]*$|^hsperfdata.*_mesos$"
    } | ForEach-Object {
        $fullPath = $_.FullName
        if($_.FullName -is [System.IO.DirectoryInfo]) {
            cmd.exe /C "rmdir /s /q ${fullPath} > nul 2>&1"
        } else {
            cmd.exe /C "del /Q /S /F ${fullPath} > nul 2>&1"
        }
    }
}

function Start-MesosCITesting {
    try {
        Start-StoutTestsBuild
        Start-StdoutTestsRun
    } catch {
        Write-Output "stdout-tests failed"
    }
    try {
        Start-LibprocessTestsBuild
        Start-LibprocessTestsRun
    } catch {
        Write-Output "libprocess-tests failed"
    }
    try {
        Start-MesosTestsBuild
        Start-MesosTestsRun
    } catch {
        Write-Output "mesos-tests failed"
    }
    if($global:PARAMETERS["BUILD_STATUS"] -eq 'FAIL') {
        $errMsg = "Some of the unit tests failed. Please check the relevant logs."
        $global:PARAMETERS["FAILED_COMMAND"] = 'Start-MesosCITesting'
        Throw $errMsg
    }
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
    New-Environment
    Start-MesosBuild
    Start-MesosCITesting
    New-MesosBinaries
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
