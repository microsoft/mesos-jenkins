
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
        Copy-Item $newConfigPath $(Get-ServiceConfPath) -force
        $LASTEXITCODE | Should -Be 0
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
        $folder = md $folderpath
        "Hello at $DateStamp" | Out-File -FilePath "$folderpath/stdout" -Encoding ascii

        # Leave time for fluentd to detect change
        Sleep 2 

        $strings = Select-String -Path "$env:SystemDrive/DCOS/*.log" -Pattern "$DateStamp"
        $strings | Should -Not -Be $null
        # Remove-Item $folder -Recurse -Force
    }

}
