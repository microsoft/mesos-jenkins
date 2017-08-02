function CheckLocalPaths {
    New-Item -ItemType Directory -ErrorAction SilentlyContinue -Path $baseDir
    New-Item -ItemType Directory -ErrorAction SilentlyContinue -Path $buildDir
    New-Item -ItemType Directory -ErrorAction SilentlyContinue -Path $binariesDir
    New-Item -ItemType Directory -Force -ErrorAction SilentlyContinue -Path $logDir
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path $commitlogDir
    New-Item -ItemType Directory -Force -ErrorAction SilentlyContinue -Path $commitlogDir
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path $commitDir
    New-Item -ItemType Directory -Force -ErrorAction SilentlyContinue -Path $commitDir
    New-Item -ItemType Directory -Force -ErrorAction SilentlyContinue -Path $commitbuildDir
}

function CreateRemotePaths ($remotedirPath, $remotelnPath="") {
    $currentdirPath = ""
    $remoteCMD = "mkdir -p $remotedirPath"
    $remotelnCMD = "unlink $remotelnPath; ln -s $remotedirPath/ $remotelnPath "
    ExecSSHCmd $remoteServer $remoteUser $remoteKey $remoteCMD
    if ($remotelnPath) {
        ExecSSHCmd $remoteServer $remoteUser $remoteKey $remotelnCMD
    }
}

function GitClonePull($path, $url, $branch="master") {
    Write-Host "Cloning / pulling: $url"

    if (Test-Path -path $path) {
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path $path
    }
    
    # Start git clone
    &git clone $url $path
    if ($LastExitCode) {
        throw "git clone failed"
    }
    
    # Change branch
    &git -C $path checkout $branch
    if ($LastExitCode) {
        throw "git checkout for branch $branch failed"
    }
}

function Set-GitCommidID ( $commitID ) {
    pushd "$gitcloneDir"
    &git checkout $commitID
    write-host "this is the CommitID that we are working on"
    &git rev-parse HEAD
    popd
}

function Set-commitInfo {
	write-host "Reading and saving commit author and message."
	pushd "$gitcloneDir"
    &git log -n 1 $commitID | Out-File "$commitlogDir\message-$commitID.txt"
	#Copy-Item "$localLogs\message-$commitID.txt" -Destination "$commitlogDir\commitmessage.txt" -Force
	popd
}

function Set-VCVars($version="15.0", $platform="amd64") {
    if ($version -eq "15.0") {
        $VCPath = "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\VC\Auxiliary\Build\"
    }
    else {
        $VCPath = "$ENV:ProgramFiles (x86)\Microsoft Visual Studio $version\VC\"
    }
    pushd $VCPath
    try
    {
        cmd /c "vcvarsall.bat $platform & set" |
        foreach {
          if ($_ -match "=") {
            $v = $_.split("="); set-item -force -path "ENV:\$($v[0])"  -value "$($v[1])"
          }
        }
    }
    finally
    {
        popd
    }
}

function ExecRetry ($command, $maxRetryCount = 10, $retryInterval=2) {
    $currErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $retryCount = 0
    while ($true)
    {
        try
        {
            & $command
            break
        }
        catch [System.Exception]
        {
            $retryCount++
            if ($retryCount -ge $maxRetryCount)
            {
                $ErrorActionPreference = $currErrorActionPreference
                throw
            }
            else
            {
                Write-Error $_.Exception
                Start-Sleep $retryInterval
            }
        }
    }

    $ErrorActionPreference = $currErrorActionPreference
}

function WaitTimeout {
    Param(
        [Parameter(Mandatory=$true)]
        [String]$ProcessPath,
        [Parameter(Mandatory=$false)]
        [String[]]$ArgumentList,
        [Parameter(Mandatory=$false)]
        [String]$StdOut,
        [Parameter(Mandatory=$false)]
        [String]$StdErr,
        [Parameter(Mandatory=$false)]
        [String]$Timeout=7200
    )
    
    $parameters = @{
        'FilePath' = $ProcessPath
        'NoNewWindow' = $true
        'PassThru' = $true
    }
    if ($ArgumentList.Count -gt 0) {
        $parameters['ArgumentList'] = $ArgumentList
    }
    if ($StdOut) {
        $parameters['RedirectStandardOutput'] = $StdOut
    }
    if ($StdErr) {
        $parameters['RedirectStandardError'] = $StdErr
    }

    $process = Start-Process @parameters
    
    try
    {
        Wait-Process -InputObject $process -Timeout $Timeout -ErrorAction Stop
        Write-Warning -Message 'Process successfully completed within Timeout.'
    }
    catch
    {
        Write-Warning -Message 'Process either exceeded Timeout or exited with non-zero value.'
        Stop-Process -InputObject $process -Force -ErrorAction SilentlyContinue
        throw $_
    }
}

function ExecSSHCmd ($server, $user, $key, $cmd) {
    write-host "Running ssh command $cmd on remote server $server"
    echo Y | plink.exe $server -l $user -i $key $cmd
}

function ExecSCPCmd ($server, $user, $key, $localPath, $remotePath) {
    write-host "Starting copying $localPath to remote location ${server}:${remotePath}"
    echo Y | pscp.exe -scp -r -i $key $localPath $user@${server}:${remotePath}
}

function Copy-RemoteLogs ($locallogPath, $remotelogPath) {
    write-host "Started copying logs to remote location ${server}:${remotelogPath}"
    ExecSCPCmd $remoteServer $remoteUser $remoteKey $locallogPath $remotelogPath
}

function Copy-RemoteBinaries ($localbinariesPath, $remotebinariesPath) {
    write-host "Started copying generated binaries to remote location ${server}:${remotebinariesPath}"
    ExecSCPCmd $remoteServer $remoteUser $remoteKey $localbinariesPath $remotebinariesPath
}

function CompressBinaries ($filePath, $archiveName) {
    $arrEXE = Get-ChildItem $filePath -Filter *.exe | Foreach-Object {$_.FullName}
    & 7z.exe a -tzip $archiveName $arrEXE -sdel
}

function CompressPDB ($filePath, $archiveName) {
    $arrPDB = Get-ChildItem $filePath -Filter *.pdb | Foreach-Object {$_.FullName}
    & 7z.exe a -tzip $archiveName $arrPDB -sdel
}

function CompressAll ($filePath, $archivePath) {
    $arrEXE = Get-ChildItem $filePath | Foreach-Object {$_.FullName}
    & 7z.exe a -tzip $archivePath $arr -sdel
}

function CompressLogs ( $logsPath ) {
    $logfiles = Get-ChildItem -File -Recurse -Path $logsPath | Where-Object { $_.Extension -ne ".gz" }
    foreach ($file in $logfiles) {
        $filename = $file.name
        $directory = $file.DirectoryName
        $extension = $file.extension
        if (!$extension) {
            $name = $file.name + ".txt"
        }
        else {
            $name = $file.name
        }
        &7z.exe a -tgzip "$directory\$name.gz" "$directory\$filename" -sdel
    }
}

function CleanupFailedJob {
    cd $env:WORKSPACE
    Copy-Item -Force -ErrorAction SilentlyContinue "$env:WORKSPACE\mesos-build-$branch-$env:BUILD_NUMBER.log" "$commitlogDir\console.log"
    Copy-RemoteLogs "$commitlogDir\*" "$remotelogdirPath"
    CleanupJob
}

function CleanupJob {
    if ($is_debug -eq "yes") {
        write-host "This is a debug job. Not running cleanup"
        return 0
    }
    write-host "Starting Cleanup"
    $stoutprocess = Get-Process stout* -ErrorAction SilentlyContinue
    $libprocess = Get-Process libprocess* -ErrorAction SilentlyContinue
    $mesosprocess = Get-Process mesos* -ErrorAction SilentlyContinue
    $msbuildprocess = Get-Process MSBuild* -ErrorAction SilentlyContinue
    $cmakeprocess = Get-Process cmake* -ErrorAction SilentlyContinue
    if ($stoutprocess) {Stop-Process -name stout*}
    if ($libprocess) {Stop-Process -name libprocess*}
    if ($mesosprocess) {Stop-Process -name mesos*}
    if ($msbuildprocess) {Stop-Process -name MSBuild*}
    if ($cmakeprocess) {Stop-Process -name cmake*}
    Start-Sleep -s 20
    write-host "Removing $commitDir"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path "$commitDir"
    #Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path "$env:WORKSPACE\mesos-build-1_2_x-$env:BUILD_NUMBER.log"
}

function CopyLocalBinaries ($binaries_src, $binaries_dst) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path $binaries_dst
    New-Item -ItemType Directory -ErrorAction SilentlyContinue -Path $binaries_dst
    if ( Test-Path -Path $binaries_src ) {
        Copy-Item -Force -ErrorAction SilentlyContinue -Exclude @("mesos-tests.exe","test-helper.exe") "$binaries_src\*.exe" "$binaries_dst\"
        Copy-Item -Force -ErrorAction SilentlyContinue -Exclude @("mesos-tests.pdb","test-helper.pdb") "$binaries_src\*.pdb" "$binaries_dst\"
    }
}
