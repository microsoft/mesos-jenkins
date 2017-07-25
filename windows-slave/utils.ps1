function CheckLocalPaths {
    New-Item -ItemType Directory -ErrorAction SilentlyContinue -Path $baseDir
    New-Item -ItemType Directory -ErrorAction SilentlyContinue -Path $buildDir
    New-Item -ItemType Directory -Force -ErrorAction SilentlyContinue -Path $logDir
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path $commitlogDir
    New-Item -ItemType Directory -Force -ErrorAction SilentlyContinue -Path $commitlogDir
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path $commitDir
    New-Item -ItemType Directory -Force -ErrorAction SilentlyContinue -Path $commitDir
    New-Item -ItemType Directory -Force -ErrorAction SilentlyContinue -Path $commitbuildDir
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

function Set-VCVars($version="12.0", $platform="amd64") {
    pushd "$ENV:ProgramFiles (x86)\Microsoft Visual Studio $version\VC\"
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

function Cleanup {
    $msbuildprocess = Get-Process MSBuild* -ErrorAction SilentlyContinue
    $cmakeprocess = Get-Process cmake* -ErrorAction SilentlyContinue
    if ($msbuildprocess) {
        Stop-Process -name MSBuild*
    }
    if ($cmakeprocess) {
        Stop-Process -name cmake*
    }
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path $commitDir
}

function CopyBinaries {
    $binaries_path = "$commitbuildDir\src"
    if ( Test-Path -Path $binaries_path ) {
        Copy-Item -Force "$binaries_path\*.exe" "$commitbinariesDir\"
    }
}
