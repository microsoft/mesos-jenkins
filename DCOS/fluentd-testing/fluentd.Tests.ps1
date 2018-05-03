
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$newConfigPath = Join-Path $here td-agent.conf

function Get-ServiceConfPath() {
    $serviceInfo = Get-ItemProperty -PATH HKLM:\SYSTEM\CurrentControlSet\Services\fluentdwinsvc
    $confPath = $serviceInfo.fluentdopt -split " " | where {$_ -like "*.conf"}
    return $confPath
}

Describe "Fluentd sanity check" {

    It "Service can be found" {
        $service = Get-Service "fluentdwinsvc"
        $service | Should -Not -Be $null
    }

    It "Service is running" {
        $service = Get-Service "fluentdwinsvc"
        $service.Status | Should -Be "Running"
    }

    It "Can find custom config in current directory" {
        Test-Path $newConfigPath -PathType Leaf | Should -Be $true
    }

    It "Can get get service opts" {
        Get-ServiceConfPath | Should -Not -Be $null
    }
}


Describe "Fluentd logging" {

    It "Can modify conf file" {
        { Copy-Item $newConfigPath $(Get-ServiceConfPath) -force } | Should Not Throw
    }

    It "Can restart service to update config" {
        # Requires Admin rights
        Restart-Service -Name fluentdwinsvc
        $service = Get-Service fluentdwinsvc
        $service.Status | Should -Be "Running"
    }

    It "Can see changes to file in dynamic directory" {
        [String] $DateStamp = get-date -Format yyyyMMddTHHmmss
        $folderpath = "$env:SystemDrive/DCOS/mesos/$DateStamp"
        $folder = mkdir $folderpath
        $folder | Should Not Be $null
        "Hello at $DateStamp" | Out-File -FilePath "$folderpath/stdout" -Encoding ascii

        # Retry to Leave time for fluentd to detect change
        $retry = 30
        $found = $null
        while ($retry -gt 0 -and $found -eq $null) {
            $found = Select-String -Path "$env:SystemDrive/DCOS/*.log" -Pattern "$DateStamp"
            Start-Sleep 1
            $retry -= 1
            Write-Host "Retries left : $retry"
        }
        $found | Should -Not -Be $null
    }

}
