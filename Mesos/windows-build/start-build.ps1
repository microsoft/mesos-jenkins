Param(
    [Parameter(Mandatory=$false)]
    [string]$ReviewID,
    [Parameter(Mandatory=$false)]
    [string]$Branch="master",
    [Parameter(Mandatory=$false)]
    [string]$CommitID,
    [Parameter(Mandatory=$false)]
    [string]$ParametersFile="${env:WORKSPACE}\build-parameters.txt"
)

$ErrorActionPreference = "Stop"

$globalVariables = (Resolve-Path "$PSScriptRoot\..\..\global-variables.ps1").Path
$ciUtils = (Resolve-Path "$PSScriptRoot\..\..\Modules\CIUtils").Path

Import-Module $ciUtils
. $globalVariables


function Install-Prerequisites {
    $prerequisites = @{
        'git'= @{
            'url'= $GIT_URL
            'install_args' = @("/SILENT")
            'install_dir' = $GIT_DIR
        }
        'cmake'= @{
            'url'= $CMAKE_URL
            'install_args'= @("/quiet")
            'install_dir'= $CMAKE_DIR
        }
        'gnuwin32'= @{
            'url'= $GNU_WIN32_URL
            'install_args'= @("/VERYSILENT","/SUPPRESSMSGBOXES","/SP-")
            'install_dir'= $GNU_WIN32_DIR
        }
        'python27'= @{
            'url'= $PYTHON_URL
            'install_args'= @("/qn")
            'install_dir'= $PYTHON_DIR
        }
        'putty'= @{
            'url'= $PUTTY_URL
            'install_args'= @("/q")
            'install_dir'= $PUTTY_DIR
        }
        '7zip'= @{
            'url'= $7ZIP_URL
            'install_args'= @("/q")
            'install_dir'= $7ZIP_DIR
        }
        'vs2017'= @{
            'url'= $VS2017_URL
            'install_args'= @(
                "--quiet",
                "--add", "Microsoft.VisualStudio.Component.CoreEditor",
                "--add", "Microsoft.VisualStudio.Workload.NativeDesktop",
                "--add", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
                "--add", "Microsoft.VisualStudio.Component.VC.DiagnosticTools",
                "--add", "Microsoft.VisualStudio.Component.Windows10SDK.15063.Desktop",
                "--add", "Microsoft.VisualStudio.Component.VC.CMake.Project",
                "--add", "Microsoft.VisualStudio.Component.VC.ATL"
            )
            'install_dir'= $VS2017_DIR
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
        Invoke-WebRequest -UseBasicParsing -Uri $prerequisites[$program]['url'] -OutFile $programFile
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
            Throw "Failed to install prerequisite: $programFile"
        }
    }
}

function Add-ReviewBoardPatch {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$PatchID
    )
    Write-Output "Applying Reviewboard patch(es) over Mesos $Branch branch"
    $tempFile = Join-Path $env:TEMP "mesos_dependent_review_ids"
    $logsUrl = Get-BuildLogsUrl
    try {
        $fileName = "get-review-ids.log"
        $errMsg = "Failed to get dependent review IDs for patch $PatchID. Please check $logsUrl/$fileName for any relevant errors"
        python.exe "$MESOS_JENKINS_GIT_REPO_DIR\Mesos\utils\get-review-ids.py" -r $PatchID -o $tempFile | Tee-Object -FilePath "$MESOS_BUILD_LOGS_DIR\$fileName"
        if ($LASTEXITCODE) { Throw $errMsg }
    } catch {
        Add-Content -Path $ParametersFile -Value "STATUS=ERROR"
        Add-Content -Path $ParametersFile -Value "MESSAGE=$errMsg"
        Throw $_
    }
    $reviewIDs = Get-Content $tempFile
    Write-Output "Patches IDs that need to be applied: $reviewIDs"
    Push-Location $MESOS_GIT_REPO_DIR
    foreach($id in $reviewIDs) {
        Write-Output "Applying patch ID: $id"
        try {
            $fileName = "apply-reviews.log"
            $errMsg = "Failed to apply patch $id. Please check $logsUrl/$fileName for any relevant errors"
            python.exe ".\support\apply-reviews.py" -n -r $id | Tee-Object -Append -FilePath "$MESOS_BUILD_LOGS_DIR\$fileName"
            if ($LASTEXITCODE) { Throw $errMsg }
        } catch {
            Add-Content -Path $ParametersFile -Value "STATUS=ERROR"
            Add-Content -Path $ParametersFile -Value "MESSAGE=$errMsg"
            Pop-Location
            Throw $_
        }
    }
    Pop-Location
    Write-Output "Finished applying Reviewboard patch(es)"
}

function Set-LatestMesosCommit {
    Push-Location $MESOS_GIT_REPO_DIR
    try {
        if($CommitID) {
            Start-ExternalCommand { git.exe reset --hard $CommitID } -ErrorMessage "Failed to set Mesos last commit to: $CommitID"
        }
        Start-ExternalCommand { git.exe log -n 1 } -ErrorMessage "Failed to get latest commit message" | Out-File "$MESOS_BUILD_LOGS_DIR\latest-commit.log"
        $mesosCommitId = Start-ExternalCommand { git.exe log --format="%H" -n 1 } -ErrorMessage "Failed to get latest commit id"
        Set-Variable -Name "LATEST_COMMIT_ID" -Value $mesosCommitId -Scope Global -Option ReadOnly
    } catch {
        Pop-Location
        Throw $_
    }
    Pop-Location
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
    New-Directory $MESOS_BUILD_DIR
    New-Directory $MESOS_BINARIES_DIR
    New-Directory $MESOS_BUILD_OUT_DIR -RemoveExisting
    New-Directory $MESOS_BUILD_LOGS_DIR
    if(Test-Path $ParametersFile) {
        Remove-Item -Force $ParametersFile
    }
    New-Item -ItemType File -Path $ParametersFile
    Add-Content -Path $ParametersFile -Value "BRANCH=$Branch"
    # Clone Mesos repository
    Start-GitClone -Path $MESOS_GIT_REPO_DIR -URL $MESOS_GIT_URL -Branch $Branch
    Set-LatestMesosCommit
    Start-GitClone -Path $MESOS_JENKINS_GIT_REPO_DIR -URL $MESOS_JENKINS_GIT_URL -Branch 'master'
    if($ReviewID) {
        # Pull the patch is a review ID was given
        Add-ReviewBoardPatch -PatchID $ReviewID
    }
    Write-Output "Created new tests environment"
}

function Start-MesosBuild {
    Write-Output "Building Mesos"
    Push-Location $MESOS_DIR
    if($Branch -eq "master") {
        $generatorName = "Visual Studio 15 2017 Win64"
    } else {
        $generatorName = "Visual Studio 14 2015 Win64"
    }
    try {
        $logFileName = "mesos-cmake-build.log"
        $logsUrl = Get-BuildLogsUrl
        $errMsg = "Mesos failed to build. Please check $logsUrl\$logFileName for any relevant errors"
        cmake.exe "$MESOS_GIT_REPO_DIR" -G $generatorName -T "host=x64" -DENABLE_LIBEVENT=1 -DHAS_AUTHENTICATION=0 | Tee-Object -FilePath "$MESOS_BUILD_LOGS_DIR\$logFileName"
        if($LASTEXITCODE) { Throw $errMsg }
    } catch {
        Add-Content -Path $ParametersFile -Value "STATUS=FAIL"
        Add-Content -Path $ParametersFile -Value "MESSAGE=$errMsg"
        Pop-Location
        Throw $_
    }
    Write-Output "Mesos successfully was successfully built"
    Pop-Location
}

function Start-STDOutTests {
    Write-Output "Started Mesos stdout-tests build"
    Push-Location $MESOS_DIR
    $logsUrl = Get-BuildLogsUrl
    try {
        $logFileName = "stout-tests-cmake-build.log"
        $errMsg = "Mesos stdout-tests failed to build. Please check $logsUrl/$logFileName for any relevant errors"
        cmake.exe --build . --target stout-tests --config Debug | Tee-Object -FilePath "$MESOS_BUILD_LOGS_DIR\$logFileName"
        if($LASTEXITCODE) { Throw $errMsg }
    } catch {
        Add-Content -Path $ParametersFile -Value "STATUS=FAIL"
        Add-Content -Path $ParametersFile -Value "MESSAGE=$errMsg"
        Pop-Location
        Throw $_
    }
    Write-Output "stdout-tests were successfully built"
    Write-Output "Started Mesos stdout-tests run"
    try {
        $stdoutLogFileName = "stdout-tests-stdout.log"
        $stderrLogFileName = "stdout-tests-stderr.log"
        $stdoutUrl = "$logsUrl/$stdoutLogFileName"
        $stderrUrl = "$logsUrl/$stderrLogFileName"
        $errMsg = "Some Mesos stdout-tests failed. Please check $stdoutUrl and $stderrUrl for any relevant errors."
        Wait-ProcessToFinish -ProcessPath "$MESOS_DIR\3rdparty\stout\tests\Debug\stout-tests.exe" `
                             -StandardOutput "$MESOS_BUILD_LOGS_DIR\$stdoutLogFileName" `
                             -StandardError "$MESOS_BUILD_LOGS_DIR\$stderrLogFileName"
    } catch {
        Add-Content -Path $ParametersFile -Value "STATUS=FAIL"
        Add-Content -Path $ParametersFile -Value "MESSAGE=$errMsg"
        Pop-Location
        Throw $_
    } finally {
        Write-Output "stdout-tests standard output available at: $stdoutUrl"
        Write-Output "stdout-tests standard error available at: $stderrUrl"
    }
    Write-Output "stdout-tests PASSED"
    Pop-Location
}

function Start-LibProcessTests {
    Write-Output "Started Mesos libprocess-tests build"
    Push-Location $MESOS_DIR
    $logsUrl = Get-BuildLogsUrl
    try {
        $logFileName = "libprocess-tests-cmake-build.log"
        $errMsg = "Mesos libprocess-tests failed to build. Please check $logsUrl/$logFileName for any relevant errors"
        cmake.exe --build . --target libprocess-tests --config Debug | Tee-Object -FilePath "$MESOS_BUILD_LOGS_DIR\$logFileName"
        if($LASTEXITCODE) { Throw $errMsg }
    } catch {
        Add-Content -Path $ParametersFile -Value "STATUS=FAIL"
        Add-Content -Path $ParametersFile -Value "MESSAGE=$errMsg"
        Pop-Location
        Throw $_
    }
    Write-Output "libprocess-tests finished building"
    Write-Output "Started Mesos libprocess-tests run"
    try {
        $stdoutLogFileName = "libprocess-tests-stdout.log"
        $stderrLogFileName = "libprocess-tests-stderr.log"
        $stdoutUrl = "$logsUrl/$stdoutLogFileName"
        $stderrUrl = "$logsUrl/$stderrLogFileName"
        $errMsg = "Some Mesos libprocess-tests failed. Please check $stdoutUrl and $stderrUrl for any relevant errors"
        Wait-ProcessToFinish -ProcessPath "$MESOS_DIR\3rdparty\libprocess\src\tests\Debug\libprocess-tests.exe" `
                             -StandardOutput "$MESOS_BUILD_LOGS_DIR\$stdoutLogFileName" `
                             -StandardError "$MESOS_BUILD_LOGS_DIR\$stderrLogFileName"
    } catch {
        Add-Content -Path $ParametersFile -Value "STATUS=FAIL"
        Add-Content -Path $ParametersFile -Value "MESSAGE=$errMsg"
        Pop-Location
        Throw $_
    } finally {
        Write-Output "libprocess-tests standard output available at: $stdoutUrl"
        Write-Output "libprocess-tests standard error available at: $stderrUrl"
    }
    Write-Output "libprocess-tests PASSED"
    Pop-Location
}

function Start-MesosTests {
    Write-Output "Started Mesos tests build"
    Push-Location $MESOS_DIR
    $logsUrl = Get-BuildLogsUrl
    try {
        $logFileName = "mesos-tests-cmake-build.log"
        $errMsg = "Mesos tests failed to build. Please check $logsUrl/$logFileName for any relevant errors"
        cmake.exe --build . --target mesos-tests --config Debug | Tee-Object -FilePath "$MESOS_BUILD_LOGS_DIR\$logFileName"
        if($LASTEXITCODE) { Throw $errMsg }
    } catch {
        Add-Content -Path $ParametersFile -Value "STATUS=FAIL"
        Add-Content -Path $ParametersFile -Value "MESSAGE=$errMsg"
        Pop-Location
        Throw $_
    }
    Write-Output "Mesos tests successfully built"
    Write-Output "Started Mesos tests run"
    try {
        $stdoutLogFileName = "mesos-tests-stdout.log"
        $stderrLogFileName = "mesos-tests-stderr.log"
        $stdoutUrl = "$logsUrl/$stdoutLogFileName"
        $stderrUrl = "$logsUrl/$stderrLogFileName"
        $errMsg = "Some Mesos tests failed. Please check $stdoutUrl and $stderrUrl for any relevant errors"
        Wait-ProcessToFinish -ProcessPath "$MESOS_DIR\src\mesos-tests.exe" `
                             -ArgumentList @("--verbose") `
                             -StandardOutput "$MESOS_BUILD_LOGS_DIR\$stdoutLogFileName" `
                             -StandardError "$MESOS_BUILD_LOGS_DIR\$stderrLogFileName"
        Get-Content $stdOutFile
    } catch {
        Add-Content -Path $ParametersFile -Value "STATUS=FAIL"
        Add-Content -Path $ParametersFile -Value "MESSAGE=$errMsg"
        Pop-Location
        Throw $_
    } finally {
        Write-Output "mesos-tests standard output available at: $stdoutUrl"
        Write-Output "mesos-tests standard error available at: $stderrUrl"
    }
    Write-Output "mesos-tests PASSED"
    Pop-Location
}

function New-MesosBinaries {
    Push-Location $MESOS_DIR
    # After the tests finished and all PASSED is time to build the Mesos binaries
    Write-Output "Started building Mesos binaries"
    $logsUrl = Get-BuildLogsUrl
    try {
        $fileName = "mesos-binaries-cmake-build.log"
        $errMsg = "Mesos binaries failed to build. Please check $logsUrl/$fileName for any relevant errors"
        cmake.exe --build . | Tee-Object -FilePath "$MESOS_BUILD_LOGS_DIR\$fileName"
        if($LASTEXITCODE) { Throw $errMsg }
    } catch {
        Add-Content -Path $ParametersFile -Value "STATUS=FAIL"
        Add-Content -Path $ParametersFile -Value "MESSAGE=$errMsg"
        Pop-Location
        Throw $_
    }
    Write-Output "Successfully generated Mesos binaries"
    New-Directory $MESOS_BUILD_BINARIES_DIR
    Copy-Item -Force -Exclude @("mesos-tests.exe","test-helper.exe") -Path "$MESOS_DIR\src\*.exe" -Destination "$MESOS_BUILD_BINARIES_DIR\mesos\"
    Compress-Files -FilesDirectory "$MESOS_BUILD_BINARIES_DIR\mesos\" -Filter "*.exe" -Archive "$MESOS_BUILD_BINARIES_DIR\mesos-binaries.zip"
    Copy-Item -Force -Exclude @("mesos-tests.pdb","test-helper.pdb") -Path "$MESOS_DIR\src\*.pdb" -Destination "$MESOS_BUILD_BINARIES_DIR\mesos\"
    Compress-Files -FilesDirectory "$MESOS_BUILD_BINARIES_DIR\mesos\" -Filter "*.pdb" -Archive "$MESOS_BUILD_BINARIES_DIR\mesos-pdb.zip"
    Pop-Location
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

function Get-RemoteBuildDirectoryPath {
    if($ReviewID) {
        return "$REMOTE_MESOS_BUILD_DIR/review/$ReviewID"
    }
    $mesosCommitID = Get-LatestCommitID
    return "$REMOTE_MESOS_BUILD_DIR/$Branch/$mesosCommitID"
}

function Get-RemoteLatestSymlinkPath {
    if($ReviewID) {
        return "$REMOTE_MESOS_BUILD_DIR/review/latest"
    }
    return "$REMOTE_MESOS_BUILD_DIR/$Branch/latest"
}

function Get-BuildOutputsUrl {
    if($ReviewID) {
        return "$MESOS_BUILD_BASE_URL/review/$ReviewID"
    }
    $mesosCommitID = Get-LatestCommitID
    return "$MESOS_BUILD_BASE_URL/$Branch/$mesosCommitID"
}

function Get-BuildLogsUrl {
    $buildOutUrl = Get-BuildOutputsUrl
    return "$buildOutUrl/logs"
}

function Get-BuildBinariesUrl {
    $buildOutUrl = Get-BuildOutputsUrl
    return "$buildOutUrl/binaries"
}

function Start-LogServerFilesUpload {
    Param(
        [Parameter(Mandatory=$false)]
        [switch]$CreateLatestSymlink
    )
    Copy-Item -Force "${env:WORKSPACE}\mesos-build-$Branch-${env:BUILD_NUMBER}.log" "$MESOS_BUILD_LOGS_DIR\console-jenkins.log"
    $remoteDirPath = Get-RemoteBuildDirectoryPath
    New-RemoteDirectory -RemoteDirectoryPath $remoteDirPath
    Copy-FilesToRemoteServer "$MESOS_BUILD_OUT_DIR\*" $remoteDirPath
    $logsUrl = Get-BuildLogsUrl
    Add-Content -Path $ParametersFile -Value "LOGS_URL=$logsUrl"
    $buildOutputsUrl = Get-BuildOutputsUrl
    Add-Content -Path $ParametersFile -Value "BUILD_OUTPUTS_URL=$buildOutputsUrl"
    Write-Output "Logs can be found at: $logsUrl"
    if((Test-Path $MESOS_BUILD_BINARIES_DIR)) {
        # This means that binaries build was successful and binaries were generated.
        $binariesUrl = Get-BuildBinariesUrl
        Write-Output "Binaries can be found at: $binariesUrl"
    }
    if($CreateLatestSymlink) {
        $remoteSymlinkPath = Get-RemoteLatestSymlinkPath
        New-RemoteSymlink -RemotePath $remoteDirPath -RemoteSymlinkPath $remoteSymlinkPath
    }
}

function Start-EnvironmentCleanup {
    # Stop any potential hanging process
    $processes = @('python', 'git', 'cl', 'cmake',
                   'stdout-tests', 'libprocess-tests', 'mesos-tests')
    $processes | Foreach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
    Invoke-Expression -Command "cmd /C rmdir /s /q $MESOS_DIR" -ErrorAction SilentlyContinue
}


try {
    Install-Prerequisites
    $toolsDirs = @(
        "$CMAKE_DIR\bin",
        "$GIT_DIR\cmd",
        "$GIT_DIR\bin",
        "$PYTHON_DIR",
        "$PYTHON_DIR\Scripts",
        "$7ZIP_DIR"
    )
    $env:PATH += ';' + ($toolsDirs -join ';')
    Start-ExternalCommand { git.exe config --global user.email "ibalutoiu@cloudbasesolutions.com" } -ErrorMessage "Failed to set git user email"
    Start-ExternalCommand { git.exe config --global user.name "ionutbalutoiu" } -ErrorMessage "Failed to set git user name"
    # Set Visual Studio variables based on tested branch
    if ($branch -eq "master") {
        Set-VCVariables "15.0"
    } else {
        Set-VCVariables "14.0"
    }
    New-Environment
    Start-MesosBuild
    Start-STDOutTests
    Start-LibProcessTests
    Start-MesosTests
    New-MesosBinaries
    Add-Content $ParametersFile "STATUS=PASS"
    if($ReviewID) {
        $msg = "Mesos patch $ReviewID was successfully built and tested."
    } else {
        $msg = "Mesos nightly build and testing was successful."
    }
    Add-Content $ParametersFile "MESSAGE=$msg"
    Start-LogServerFilesUpload -CreateLatestSymlink
    Start-EnvironmentCleanup
} catch {
    $errMsg = $_.ToString()
    Write-Output $errMsg
    $status = Get-Content $ParametersFile | Where-Object { $_.StartsWith('STATUS=') }
    $message = Get-Content $ParametersFile | Where-Object { $_.StartsWith('MESSAGE=') }
    if(!$status -and !$message) {
        Add-Content -Path $ParametersFile -Value "STATUS=ERROR"
        Add-Content -Path $ParametersFile -Value "MESSAGE=$errMsg"
    }
    Start-LogServerFilesUpload
    Start-EnvironmentCleanup
    exit 1
}