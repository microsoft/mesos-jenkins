Param(
    [Parameter(Mandatory=$false)]
    [string]$GitURL="https://github.com/dcos/dcos-diagnostics", 
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
            Throw "Failed to install prerequisite $programFile during the environment setup"
        }
    }
    # Add all the tools to PATH
    $toolsDirs = @("$GOLANG_DIR\bin", "$GIT_DIR\cmd", "$GIT_DIR\bin", "$7ZIP_DIR")
    $env:PATH += ';' + ($toolsDirs -join ';')
}

function Start-DiagnosticsCIProcess {
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
    $stdoutFile = Join-Path $DIAGNOSTICS_BUILD_LOGS_DIR $StdoutFileName
    $stderrFile = Join-Path $DIAGNOSTICS_BUILD_LOGS_DIR $StderrFileName
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
        Throw "Failed to get the latest dcos-diagnostics commit ID. Perhaps it has not saved."
    }
    return $global:LATEST_COMMIT_ID
}

function Set-LatestDiagnosticsCommit {
    Push-Location $DIAGNOSTICS_GIT_REPO_DIR
    try {
        if($CommitID) {
            Start-ExternalCommand { git.exe reset --hard $CommitID } -ErrorMessage "Failed to set Diagnostics git repo last commit to: $CommitID."
        }
        Start-ExternalCommand { git.exe log -n 1 } -ErrorMessage "Failed to get the latest commit message for the Diagnostics git repo" | Out-File "$DIAGNOSTICS_BUILD_LOGS_DIR\latest-commit.log"
        $commitId = Start-ExternalCommand { git.exe log --format="%H" -n 1 } -ErrorMessage "Failed to get the latest commit id for the dcos-diagnostics git repo"
        Set-Variable -Name "LATEST_COMMIT_ID" -Value $commitId -Scope Global  -Option ReadOnly
    } finally {
        Pop-Location
    }
}

function New-TestingEnvironment {
    Write-Output "Creating new tests environment"
    Start-EnvironmentCleanup # Do an environment cleanup to make sure everything is fresh
    New-Directory $DIAGNOSTICS_DIR
    New-Directory $DIAGNOSTICS_BUILD_OUT_DIR -RemoveExisting
    New-Directory $DIAGNOSTICS_BUILD_LOGS_DIR
    $global:PARAMETERS["BRANCH"] = $Branch
    Start-GitClone -Path $DIAGNOSTICS_GIT_REPO_DIR -URL $GitURL -Branch $Branch
    Set-LatestDiagnosticsCommit
    $env:GOPATH = $DIAGNOSTICS_DIR
    $env:PATH = "${env:GOPATH}\bin;" + ${env:PATH}
    Write-Output "New tests environment was successfully created"
}

function Start-DCOSDiagnosticsBuild {
    Write-Output "Building DC/OS Diagnostics"
    Push-Location $DIAGNOSTICS_GIT_REPO_DIR
    try {
        Start-DiagnosticsCIProcess  -ProcessPath "powershell.exe" `
                                    -StdoutFileName "diagnostics-build-stdout.log" `
                                    -StderrFileName "diagnostics-build-stderr.log" `
                                    -ArgumentList @(".\scripts\make.ps1", "build") `
                                    -BuildErrorMessage "Diagnostics failed to build."
    } finally {
        Pop-Location
    }
    Write-Output "DC/OS Diagnostics was successfully built"
}

function New-DCOSDiagnosticsPackage {
    Write-Output "Creating DC/OS Diagnostics package"
    Write-Output "DIAGNOSTICS_GIT_REPO_DIR: $DIAGNOSTICS_GIT_REPO_DIR"
    New-Directory $DIAGNOSTICS_BUILD_BINARIES_DIR
    Copy-Item -Path "$PSScriptRoot\utils\detect_ip.ps1" -Destination $DIAGNOSTICS_BUILD_BINARIES_DIR
    Copy-Item -Recurse -Path "$PSScriptRoot\config" -Destination $DIAGNOSTICS_BUILD_BINARIES_DIR
    Copy-Item -Force -Path "$DIAGNOSTICS_GIT_REPO_DIR\*.exe" -Destination "$DIAGNOSTICS_BUILD_BINARIES_DIR\"
    Compress-Files -FilesDirectory "$DIAGNOSTICS_BUILD_BINARIES_DIR\" -Filter "*.*" -Archive "$DIAGNOSTICS_BUILD_BINARIES_DIR\diagnostics.zip"
    Write-Output "DC/OS Diagnostics package was successfully generated"
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

function Get-DiagnosticsBuildRelativePath {
    $repositoryName = $GitURL.Split("/")[-1]
    $diagnosticsCommitID = Get-LatestCommitID
    return "${repositoryName}-${Branch}-${diagnosticsCommitID}"
}

function Get-RemoteBuildDirectoryPath {
    $relativePath = Get-DiagnosticsBuildRelativePath
    return "$ARTIFACTS_DIRECTORY/${env:JOB_NAME}/${env:BUILD_ID}/$relativePath"
}

function Get-BuildOutputsUrl {
    $relativePath = Get-DiagnosticsBuildRelativePath
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
    $latestPath = "${ARTIFACTS_DIRECTORY}/${env:JOB_NAME}/latest-diagnostics-build"
    New-RemoteSymlink -RemotePath $remoteDirPath -RemoteSymlinkPath $latestPath
}

function Start-LogServerFilesUpload {
    $consoleUrl = "${env:JENKINS_URL}/job/${env:JOB_NAME}/${env:BUILD_NUMBER}/consoleText"
    Start-FileDownload -User ${env:JENKINS_USER} -Password ${env:JENKINS_PASSWORD} `
                       -URL $consoleUrl -Destination "$DIAGNOSTICS_BUILD_LOGS_DIR\console-jenkins.log"
    $remoteDirPath = Get-RemoteBuildDirectoryPath
    New-RemoteDirectory -RemoteDirectoryPath $remoteDirPath
    Copy-FilesToRemoteServer "$DIAGNOSTICS_BUILD_OUT_DIR\*" $remoteDirPath
    $buildOutputsUrl = Get-BuildOutputsUrl
    $global:PARAMETERS["BUILD_OUTPUTS_URL"] = $buildOutputsUrl
    Write-Output "Build artifacts can be found at: $buildOutputsUrl"
    if($global:PARAMETERS["BUILD_STATUS"] -eq "PASS") {
        New-RemoteLatestSymlinks
    }
 }

function Start-EnvironmentCleanup {
    # Stop any potential hanging process
    $processes = @('go', 'bash')
    $processes | Foreach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
    cmd.exe /C "rmdir /s /q $DIAGNOSTICS_DIR > nul 2>&1"
}

function Get-SuccessBuildMessage {
    return "Successful DC/OS Diagnostics Windows build and testing for repository $GitURL on $Branch branch"
}

function Start-TempDirCleanup {
    Get-ChildItem $env:TEMP | Where-Object {
        $_.Name -notmatch "^jna\-[0-9]*$|^hsperfdata.*_diagnostics$"
    } | ForEach-Object {
        $fullPath = $_.FullName
        if($_.FullName -is [System.IO.DirectoryInfo]) {
            cmd.exe /C "rmdir /s /q ${fullPath} > nul 2>&1"
        } else {
            cmd.exe /C "del /Q /S /F ${fullPath} > nul 2>&1"
        }
    }
}

function Start-DCOSDiagnosticsUnitTests {
    Write-Output "Run DC/OS Diagnostics unit tests"
    Push-Location $DIAGNOSTICS_GIT_REPO_DIR
    try {
        Start-DiagnosticsCIProcess  -ProcessPath "powershell.exe" `
                                    -StdoutFileName "diagnostics-unitests-stdout.log" `
                                    -StderrFileName "diagnostics-unitests-stderr.log" `
                                    -ArgumentList @(".\scripts\make.ps1", "test") `
                                    -BuildErrorMessage "Diagnostics failed to build."
    } finally {
        Pop-Location
    }
    Write-Output "DC/OS Diagnostics unit tests passed"
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
    Start-DCOSDiagnosticsBuild
    Start-DCOSDiagnosticsUnitTests
    New-DCOSDiagnosticsPackage
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
