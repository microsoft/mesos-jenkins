function Start-SSHCommand {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Server,
        [Parameter(Mandatory=$true)]
        [string]$User,
        [Parameter(Mandatory=$true)]
        [string]$Key,
        [Parameter(Mandatory=$true)]
        [string]$Command
    )
    Write-Output "Running the command '$Command' via SSH on remote the server $Server"
    Write-Output 'Y' | plink.exe $server -l $user -i $key $Command
    if($LASTEXITCODE) {
        Throw "Failed to excute the SSH command"
    }
}

function Start-SCPCommand {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Server,
        [Parameter(Mandatory=$true)]
        [string]$User,
        [Parameter(Mandatory=$true)]
        [string]$Key,
        [Parameter(Mandatory=$true)]
        [string]$LocalPath,
        [Parameter(Mandatory=$true)]
        [string]$RemotePath
    )
    Write-Output "Starting copying $LocalPath to remote location at ${Server}:${RemotePath}"
    Write-Output 'Y' | pscp.exe -scp -r -i $Key $LocalPath $User@${Server}:${RemotePath}
    if($LASTEXITCODE) {
        Throw "Failed to excute the SCP command"
    }

}

function Start-ExternalCommand {
    <#
    .SYNOPSIS
    Helper function to execute a script block and throw an exception in case of error.
    .PARAMETER ScriptBlock
    Script block to execute
    .PARAMETER ArgumentList
    A list of parameters to pass to Invoke-Command
    .PARAMETER ErrorMessage
    Optional error message. This will become part of the exception message we throw in case of an error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Alias("Command")]
        [ScriptBlock]$ScriptBlock,
        [array]$ArgumentList=@(),
        [string]$ErrorMessage
    )
    PROCESS {
        if($LASTEXITCODE){
            # Leftover exit code. Some other process failed, and this
            # function was called before it was resolved.
            # There is no way to determine if the ScriptBlock contains
            # a powershell commandlet or a native application. So we clear out
            # the LASTEXITCODE variable before we execute. By this time, the value of
            # the variable is not to be trusted for error detection anyway.
            $LASTEXITCODE = ""
        }
        $res = Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
        if ($LASTEXITCODE) {
            if(!$ErrorMessage){
                Throw ("Command exited with status: {0}" -f $LASTEXITCODE)
            }
            Throw ("{0} (Exit code: $LASTEXITCODE)" -f $ErrorMessage)
        }
        return $res
    }
}

function Start-GitClone {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$URL,
        [Parameter(Mandatory=$false)]
        [string]$Branch="master"
    )
    Write-Output "Cloning the git repository $URL to local path $Path"
    if(Test-Path -Path $Path) {
        Remove-Item -Recurse -Force -Path $Path
    }
    Start-ExternalCommand { git.exe clone $URL $Path } -ErrorMessage "Failed to clone the repository"
    Start-ExternalCommand { git.exe -C $Path checkout $Branch } -ErrorMessage "Failed to checkout branch $Branch"
}

function Set-VCVariables {
    Param(
        [string]$Version="15.0",
        [string]$Platform="amd64"
    )
    if($Version -eq "15.0") {
        $vcPath = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\2017\Community\VC\Auxiliary\Build\"
    } else {
        $vcPath = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio $Version\VC\"
    }
    Push-Location $vcPath
    try {
        $vcVars = Start-ExternalCommand { cmd.exe /c "vcvarsall.bat $Platform & set" } -ErrorMessage "Failed to get all VC variables"
        $vcVars | Foreach-Object {
            if ($_ -match "=") {
                $v = $_.split("=")
                Set-Item -Force -Path "ENV:\$($v[0])" -Value "$($v[1])"
            }
        }
    } catch {
        Pop-Location
    }
}


function Start-ExecuteWithRetry {
    <#
    .SYNOPSIS
    In some cases a command may fail several times before it succeeds, be it because of network outage, or a service
    not being ready yet, etc. This is a helper function to allow you to execute a function or binary a number of times
    before actually failing.

    Its important to note, that any powershell commandlet or native command can be executed using this function. The result
    of that command or powershell commandlet will be returned by this function.

    Only the last exception will be thrown, and will be logged with a log level of ERROR.
    .PARAMETER ScriptBlock
    The script block to run.
    .PARAMETER MaxRetryCount
    The number of retries before we throw an exception.
    .PARAMETER RetryInterval
    Number of seconds to sleep between retries.
    .PARAMETER RetryMessage
    Warning message logged on every failed retry.
    .PARAMETER ArgumentList
    Arguments to pass to your wrapped commandlet/command.

    .EXAMPLE
    # If the computer just booted after the machine just joined the domain, and your charm starts running,
    # it may error out until the security policy has been fully applied. In the bellow example we retry 10
    # times and wait 10 seconds between retries before we give up. If successful, $ret will contain the result
    # of Get-ADUser. If it does not, an exception is thrown. 
    $ret = Start-ExecuteWithRetry -ScriptBlock {
        Get-ADUser testuser
    } -MaxRetryCount 10 -RetryInterval 10
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Alias("Command")]
        [ScriptBlock]$ScriptBlock,
        [int]$MaxRetryCount=10,
        [int]$RetryInterval=3,
        [string]$RetryMessage,
        [array]$ArgumentList=@()
    )
    PROCESS {
        $currentErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $retryCount = 0
        while ($true) {
            try {
                $res = Invoke-Command -ScriptBlock $ScriptBlock `
                                      -ArgumentList $ArgumentList
                $ErrorActionPreference = $currentErrorActionPreference
                return $res
            } catch [System.Exception] {
                $retryCount++
                if ($retryCount -gt $MaxRetryCount) {
                    $ErrorActionPreference = $currentErrorActionPreference
                    Throw
                } else {
                    if($RetryMessage) {
                        Write-Output $RetryMessage
                    } elseif($_) {
                        Write-Output $_
                    }
                    Start-Sleep $RetryInterval
                }
            }
        }
    }
}

function Compress-Files {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$FilesDirectory,
        [Parameter(Mandatory=$true)]
        [string]$Archive,
        [Parameter(Mandatory=$true)]
        [string]$Filter
    )
    $files = Get-ChildItem $FilesDirectory -Filter $Filter | Foreach-Object { $_.FullName }
    Start-ExternalCommand { & 7z.exe a -tzip $Archive $files -sdel } -ErrorMessage "Failed to compress the files"
}

function Wait-ProcessToFinish {
    Param(
        [Parameter(Mandatory=$true)]
        [String]$ProcessPath,
        [Parameter(Mandatory=$false)]
        [String[]]$ArgumentList,
        [Parameter(Mandatory=$false)]
        [String]$StandardOutput,
        [Parameter(Mandatory=$false)]
        [String]$StandardError,
        [Parameter(Mandatory=$false)]
        [int]$Timeout=7200
    )
    $parameters = @{
        'FilePath' = $ProcessPath
        'NoNewWindow' = $true
        'PassThru' = $true
    }
    if ($ArgumentList.Count -gt 0) {
        $parameters['ArgumentList'] = $ArgumentList
    }
    if ($StandardOutput) {
        $parameters['RedirectStandardOutput'] = $StandardOutput
    }
    if ($StandardError) {
        $parameters['RedirectStandardError'] = $StandardError
    }
    $process = Start-Process @parameters
    $errorMessage = "The process $ProcessPath didn't finish successfully"
    try {
        Wait-Process -InputObject $process -Timeout $Timeout -ErrorAction Stop
        $exitCode = $process.ExitCode
        if ($exitCode -ne 0) {
            Throw $errorMessage
        }
        Write-Output "Process successfully completed within the timeout of $Timeout seconds"
    } catch {
        if(($_.ToString() -eq $errorMessage) -and $exitCode) {
            Write-Output "$errorMessage. Exit code: $exitCode"
        } else {
            Write-Output "The process $ProcessPath exceeded the timeout of $Timeout seconds"
            Stop-Process -InputObject $process -Force -ErrorAction SilentlyContinue
        }
        Throw $_
    }
}

function New-Directory {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$false)]
        [switch]$RemoveExisting
    )
    if(Test-Path $Path) {
        if($RemoveExisting) {
            # Remove if it already exist
            Remove-Item -Recurse -Force $Path
        } else {
            return
        }
    }
    return (New-Item -ItemType Directory -Path $Path)
}