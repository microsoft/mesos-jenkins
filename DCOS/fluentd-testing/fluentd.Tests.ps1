$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$fluentdTestingDir = Join-Path $env:SystemDrive "AzureData\fluentd-testing"


Describe "Fluentd sanity check" {
    It "Service is running" {
        (Get-Service "fluentdwinsvc").Status | Should Be "Running"
    }
}

Describe "Fluentd logging" {
    It "Can see changes to file in dynamic directory" {
        $dateStamp = Get-Date -Format "yyyyMMddTHHmmss"
        Set-Content -Path "$fluentdTestingDir/stdout" -Value "Hello at $DateStamp" -Encoding Ascii
        # Retry to leave time for fluentd to detect changes
        $retry = 30
        $found = $null
        while ($retry -gt 0 -and $found -eq $null) {
            $found = Select-String -Path "$fluentdTestingDir/*.log" -Pattern "$DateStamp"
            Start-Sleep 1
            $retry -= 1
            Write-Host "Retries left : $retry"
        }
        $found | Should Not Be $null
    }
}
