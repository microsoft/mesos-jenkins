Param(
    [Parameter(Mandatory=$false)]
    [string]$GitURL="https://github.com/apache/httpd", 
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
        '7zip'= @{
            'url'= $7ZIP_URL
            'install_args'= @("/q")
            'install_dir'= $7ZIP_DIR
        }
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    foreach($program in $prerequisites.Keys) {
        if(Test-Path $prerequisites[$program]['install_dir']) {
            Write-Output "$program is already installed"
            continue
        }
        Write-Output "Downloading $program from $($prerequisites[$program]['url'])"
        $fileName = $prerequisites[$program]['url'].Split('/')[-1]
        $programFile = Join-Path $env:TEMP $fileName
        Start-ExecuteWithRetry { Invoke-WebRequest -UseBasicParsing -Uri $prerequisites[$program]['url'] -OutFile $programFile} $RetryInterval 20
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
    $toolsDirs = @("$GIT_DIR\cmd", "$GIT_DIR\bin", "$7ZIP_DIR")
    $env:PATH += ';' + ($toolsDirs -join ';')
}

function Get-LatestCommitID {
    return $global:LATEST_COMMIT_ID
}

function Set-LatestAdminRouterCommit {
    # The following id is from https://www.apachelounge.com/download/VC15/binaries/httpd-2.4.33-win64-VC15.zip.txt
    $commitId = $WINDOWS_APACHEL_HTTP_SERVER_SHA256
    Set-Variable -Name "LATEST_COMMIT_ID" -Value $commitId -Scope Global  -Option ReadOnly
}

function Get-MesosJenkinsRepo {
    Write-Output "Get-MesosJenkinsRepo"
    New-Directory $ADMINROUTER_DIR | Out-Null
    New-Directory $ADMINROUTER_BUILD_OUT_DIR -RemoveExisting | Out-Null
    New-Directory $ADMINROUTER_BUILD_LOGS_DIR  -RemoveExisting | Out-Null
    $global:PARAMETERS["BRANCH"] = $Branch
    Remove-Item $ADMINROUTER_MESOS_JENKINS_GIT_REPO_DIR -Force  -Recurse -ErrorAction SilentlyContinue

    Write-Output "Cloning Mesos-Jenkins repo"    
    Start-GitClone -Path $ADMINROUTER_MESOS_JENKINS_GIT_REPO_DIR -URL $MESOS_JENKINS_GIT_URL -Branch $Branch
    Write-Output "Cloning  done"
}

function Get-ApacheServerPackage {
    Write-Output "Downloading Apache HTTP Server zip file: $WINDOWS_APACHEL_HTTP_SERVER_URL"
    $filesPath = Join-Path $env:TEMP "httpd-2.4.33-win64-VC15.zip"
    Start-ExecuteWithRetry { Invoke-WebRequest -UseBasicParsing -Uri $WINDOWS_APACHEL_HTTP_SERVER_URL -OutFile $filesPath}

    # To be sure that a download is intact and has not been tampered with from the original download side
    # we need to perform biniary hash validation
    Write-Output "Validating Hash value for downloaded file: $filesPath"
    $hashFromDowloadedFile = Get-FileHash $filesPath -Algorithm SHA256

    # validate both hashes are the same
    if ($hashFromDowloadedFile.Hash -eq $WINDOWS_APACHEL_HTTP_SERVER_SHA256) {
        Write-Output 'Hash validation test passed'
    } else {
        Throw 'Hash validation test FAILED!!'
    }

    Write-Output "Extracting binaries archive in: $ADMINROUTER_DIR"
    Expand-Archive -LiteralPath $filesPath -DestinationPath $ADMINROUTER_DIR -Force
    Remove-item $filesPath
    Write-Output "Finshed downloading"  
    Set-LatestAdminRouterCommit
}
function Generate-AdminRouterConfigFromTemplate {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$TemplateFile,
        [Parameter(Mandatory=$true)]
        [string]$OutputFile
    )
     $context = @{
        "adminrouter_install_dir" = ("$ADMINROUTER_FOR_TEMPLATE_DIR" -replace '\\', '/')
        "adminrouter_port" = ("$ADMINROUTER_AGENT_PORT")
        "local_metrics_port" = ("$METRICS_AGENT_PORT")
        "local_diagnostics_port" = ("$DIAGNOSTICS_AGENT_PORT")
        "local_pkgpanda_port" = ("$PKGPANDA_AGENT_PORT")
        "local_logging_port" = ("$LOGGING_AGENT_PORT")
        "apache_install_dir" = ("$ADMINROUTER_APACHE_DIR")
    }
    Start-RenderTemplate -TemplateFile $TemplateFile `
                         -Context $context -OutFile $OutputFile
}

function New-DCOSAdminRouterPackage {
    Write-Output "Generating DC/OS AdminRouter package $ADMINROUTER_ZIP_FILE_PATH"
    New-Directory $ADMINROUTER_BUILD_BINARIES_DIR | Out-Null
    Copy-Item -Recurse -Path "$ADMINROUTER_DIR\$ADMINROUTER_APACHE_DIR" -Destination $ADMINROUTER_BUILD_BINARIES_DIR | Out-Null

    $template = "$ADMINROUTER_MESOS_JENKINS_GIT_REPO_DIR\AdminRouter\config\template.conf"
    $configfile = "$ADMINROUTER_MESOS_JENKINS_GIT_REPO_DIR\AdminRouter\config\adminrouter.conf"
    Generate-AdminRouterConfigFromTemplate -TemplateFile $template -OutputFile $configfile
    Copy-Item -Recurse -Path "$ADMINROUTER_MESOS_JENKINS_GIT_REPO_DIR\AdminRouter\config\adminrouter.conf" -Destination "$ADMINROUTER_BUILD_BINARIES_DIR\$ADMINROUTER_APACHE_DIR\conf" | Out-Null

    Compress-Files -FilesDirectory "$ADMINROUTER_BUILD_BINARIES_DIR\" -Filter "*.*" -Archive "$ADMINROUTER_ZIP_FILE_PATH"
    Write-Output "DC/OS AdminRouter package was successfully generated"
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

function Get-AdminRouterBuildRelativePath {
    $repositoryOwner = $GitURL.Split("/")[-2]
    $commitID = Get-LatestCommitID
    return "$repositoryOwner/$Branch/$commitID"
}

function Get-RemoteBuildDirectoryPath {
    $relativePath = Get-AdminRouterBuildRelativePath
    return "$REMOTE_ADMINROUTER_BUILD_DIR/$relativePath"
}

function Get-BuildOutputsUrl {
    $relativePath = Get-AdminRouterBuildRelativePath
    return "$ADMINROUTER_BUILD_BASE_URL/$relativePath"
}

function New-RemoteLatestSymlinks {
    $remoteDirPath = Get-RemoteBuildDirectoryPath
    $baseDir = (Split-Path -Path $remoteDirPath -Parent) -replace '\\', '/'
    New-RemoteSymlink -RemotePath $remoteDirPath -RemoteSymlinkPath "$baseDir/latest"
    $repoDir = (Split-Path -Path $baseDir -Parent) -replace '\\', '/'
    New-RemoteSymlink -RemotePath $remoteDirPath -RemoteSymlinkPath "$repoDir/latest"
}

function Start-LogServerFilesUpload {
    $consoleUrl = "${JENKINS_SERVER_URL}/job/${env:JOB_NAME}/${env:BUILD_NUMBER}/consoleText"
    Start-FileDownload -Force -URL $consoleUrl -Destination "$ADMINROUTER_BUILD_LOGS_DIR\console-jenkins.log"
    $remoteDirPath = Get-RemoteBuildDirectoryPath
    New-RemoteDirectory -RemoteDirectoryPath $remoteDirPath
    Copy-FilesToRemoteServer "$ADMINROUTER_BUILD_OUT_DIR\*" $remoteDirPath
    $buildOutputsUrl = Get-BuildOutputsUrl
    $global:PARAMETERS["BUILD_OUTPUTS_URL"] = $buildOutputsUrl
    Write-Output "Build artifacts can be found at: $buildOutputsUrl"
    if($global:PARAMETERS["BUILD_STATUS"] -eq "PASS") {
        New-RemoteLatestSymlinks
    }
 }

function Start-EnvironmentCleanup {
    cmd.exe /C "rmdir /s /q $ADMINROUTER_DIR > nul 2>&1"
}

function Get-SuccessBuildMessage {
    return "Successful DC/OS AdminRouter Windows build and testing for repository $GitURL on $Branch branch"
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
    Get-MesosJenkinsRepo
    Get-ApacheServerPackage
    New-DCOSAdminRouterPackage
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
