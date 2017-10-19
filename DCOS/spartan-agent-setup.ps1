Param(
    [Parameter(Mandatory=$true)]
    [string[]]$MasterAddress,
    [string]$AgentPrivateIP,
    [switch]$Public=$false
)

$ErrorActionPreference = "Stop"

$ciUtils = (Resolve-Path "$PSScriptRoot\..\Modules\CIUtils").Path
$globalVariables = (Resolve-Path "$PSScriptRoot\..\global-variables.ps1").Path

Import-Module $ciUtils
. $globalVariables


$TEMPLATES_DIR = Join-Path $PSScriptRoot "templates"
$SPARTAN_LATEST_RELEASE_URL = "$SPARTAN_BUILD_BASE_URL/master/latest/release.zip"


function New-Environment {
    $service = Get-Service $SPARTAN_SERVICE_NAME -ErrorAction SilentlyContinue
    if($service) {
        Stop-Service -Force -Name $SPARTAN_SERVICE_NAME
        Start-ExternalCommand { sc.exe delete $SPARTAN_SERVICE_NAME } -ErrorMessage "Failed to delete exiting EPMD service"
    }
    New-Directory -RemoveExisting $SPARTAN_DIR
    New-Directory $SPARTAN_RELEASE_DIR
    New-Directory $SPARTAN_SERVICE_DIR
    New-Directory $SPARTAN_LOG_DIR
    $spartanReleaseZip = Join-Path $env:TEMP "spartan-release.zip"
    Write-Output "Downloading latest Spartan build"
    Invoke-WebRequest -UseBasicParsing -Uri $SPARTAN_LATEST_RELEASE_URL -OutFile $spartanReleaseZip
    Write-Output "Extracting Spartan zip archive to $SPARTAN_RELEASE_DIR"
    Expand-Archive -LiteralPath $spartanReleaseZip -DestinationPath $SPARTAN_RELEASE_DIR
    Remove-Item $spartanReleaseZip
}

function New-DevConBinary {
    $devConDir = Join-Path $env:TEMP "devcon"
    if(Test-Path $devConDir) {
        Remove-Item -Recurse -Force $devConDir
    }
    New-Item -ItemType Directory -Path $devConDir | Out-Null
    $devConCab = Join-Path $devConDir "devcon.cab"
    Invoke-WebRequest -UseBasicParsing -Uri $DEVCON_CAB_URL -OutFile $devConCab | Out-Null
    $devConFile = "filbad6e2cce5ebc45a401e19c613d0a28f"
    Start-ExternalCommand { expand.exe $devConCab -F:$devConFile $devConDir } -ErrorMessage "Failed to expand $devConCab" | Out-Null
    $devConBinary = Join-Path $env:TEMP "devcon.exe"
    Move-Item "$devConDir\$devConFile" $devConBinary
    Remove-Item -Recurse -Force $devConDir
    return $devConBinary
}

function Install-SpartanDevice {
    $spartanDevice = Get-NetAdapter -Name $SPARTAN_DEVICE_NAME -ErrorAction SilentlyContinue
    if($spartanDevice) {
        return
    }
    $devCon = New-DevConBinary
    Write-Output "Creating the Spartan network device"
    Start-ExternalCommand { & $devCon install "${env:windir}\Inf\Netloop.inf" "*MSLOOP" } -ErrorMessage "Failed to install the Spartan dummy interface"
    Remove-Item $devCon
    Get-NetAdapter | Where-Object { $_.DriverDescription -eq "Microsoft KM-TEST Loopback Adapter" } | Rename-NetAdapter -NewName $SPARTAN_DEVICE_NAME
}

function Set-SpartanDevice {
    $spartanDevice = Get-NetAdapter -Name $SPARTAN_DEVICE_NAME -ErrorAction SilentlyContinue
    if(!$spartanDevice) {
        Throw "Spartan network device was not found"
    }
    $spartanIPs = @("192.51.100.1", "192.51.100.2", "192.51.100.3")
    foreach($ip in $spartanIPs) {
        $address = Get-NetIPAddress -InterfaceAlias $SPARTAN_DEVICE_NAME -AddressFamily "IPv4" -IPAddress $ip -ErrorAction SilentlyContinue
        if($address) {
            continue
        }
        New-NetIPAddress -InterfaceAlias $SPARTAN_DEVICE_NAME -AddressFamily "IPv4" -IPAddress $ip -PrefixLength 32 | Out-Null
    }
    Disable-NetAdapter $SPARTAN_DEVICE_NAME -Confirm:$false
    Enable-NetAdapter $SPARTAN_DEVICE_NAME -Confirm:$false
}

function Get-UpstreamDNSResolvers {
    <#
    .SYNOPSIS
    Returns the DNS resolver(s) configured on the main interface
    #>
    $mainAddress = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq $AgentPrivateIP }
    if(!$mainAddress) {
        Throw "Could not find any NetIPAddress configured with the IP: $AgentPrivateIP"
    }
    $mainInterfaceIndex = $mainAddress.InterfaceIndex
    return (Get-DnsClientServerAddress -InterfaceIndex $mainInterfaceIndex).ServerAddresses
}

function New-SpartanWindowsAgent {
    $erlBinary = Join-Path $ERTS_DIR "bin\erl.exe"
    if(!(Test-Path $erlBinary)) {
        Throw "The erl binary $erlBinary doesn't exist. Cannot configure the Spartan agent Windows service"
    }
    $upstreamDNSResolvers = Get-UpstreamDNSResolvers | ForEach-Object { "{{" + ($_.Split('.') -join ', ') + "}, 53}" }
    $dnsZonesFile = "${SPARTAN_RELEASE_DIR}\spartan\data\zones.json" -replace '\\', '\\'
    # TODO(ibalutoiu): Instead of taking one of the masters' addresses for the exhibitor URL, we might
    #                  add an internal load balancer and use that address for the exhibitor URL.
    $exhibitorURL = "http://$($MasterAddress[0]):${EXHIBITOR_PORT}/exhibitor/v1/cluster/status"
    $context = @{
        "exhibitor_url" = $exhibitorURL
        "dns_zones_file" = $dnsZonesFile
        "upstream_resolvers" = "[$($upstreamDNSResolvers -join ', ')]"
    }
    $spartanConfigFile = Join-Path $SPARTAN_DIR "sys.spartan.config"
    Start-RenderTemplate -TemplateFile "$TEMPLATES_DIR\spartan\sys.spartan.config" -Context $context -OutFile "$SPARTAN_DIR\sys.spartan.config"
    $spartanVMArgsFile = Join-Path $SPARTAN_DIR "vm.spartan.args"
    $context = @{
        "agent_private_ip" = $AgentPrivateIP
        "epmd_port" = $EPMD_PORT
    }
    Start-RenderTemplate -TemplateFile "$TEMPLATES_DIR\spartan\vm.spartan.args" -Context $context -OutFile "$SPARTAN_DIR\vm.spartan.args"
    $spartanArguments = ("-noshell -noinput +Bd -mode embedded " + `
                         "-rootdir `"${SPARTAN_RELEASE_DIR}\spartan`" " + `
                         "-boot `"${SPARTAN_RELEASE_DIR}\spartan\releases\0.0.1\spartan`" " + `
                         "-boot_var ERTS_LIB_DIR `"${SPARTAN_RELEASE_DIR}\lib`" " + `
                         "-boot_var RELEASE_DIR `"${SPARTAN_RELEASE_DIR}\spartan`" " + `
                         "-config `"${spartanConfigFile}`" " + `
                         "-args_file `"${spartanVMArgsFile}`" -pa " + `
                         "-- foreground")
    $context = @{
        "service_name" = $SPARTAN_SERVICE_NAME
        "service_display_name" = "Spartan Windows Agent"
        "service_description" = "Windows Service for the DCOS Spartan Windows Agent"
        "service_binary" = $erlBinary
        "service_arguments" = $spartanArguments
        "log_dir" = $SPARTAN_LOG_DIR
    }
    $env:MASTER_SOURCE = "exhibitor"
    Start-ExternalCommand { setx.exe /M MASTER_SOURCE "exhibitor" } -ErrorMessage "Failed to set the Spartan MASTER_SOURCE system environment variable"
    $env:EXHIBITOR_ADDRESS = $MasterAddress[0]
    Start-ExternalCommand { setx.exe /M EXHIBITOR_ADDRESS $MasterAddress[0] } -ErrorMessage "Failed to set the Spartan EXHIBITOR_ADDRESS system environment variable"
    Start-RenderTemplate -TemplateFile "$TEMPLATES_DIR\windows-service.xml" -Context $context -OutFile "$SPARTAN_SERVICE_DIR\spartan-service.xml"
    $serviceWapper = Join-Path $SPARTAN_SERVICE_DIR "spartan-service.exe"
    Invoke-WebRequest -UseBasicParsing -Uri $SERVICE_WRAPPER_URL -OutFile $serviceWapper
    $p = Start-Process -FilePath $serviceWapper -ArgumentList @("install") -NoNewWindow -PassThru -Wait
    if($p.ExitCode -ne 0) {
        Throw "Failed to set up the Spartan Windows service. Exit code: $($p.ExitCode)"
    }
    # Temporary stop Docker service because we have port 53 bound and this needs to be used by Spartan
    # TODO(ibalutoiu): Permanently disable the Docker embedded DNS and remove this workaround
    Stop-Service "Docker"

    Start-Service $SPARTAN_SERVICE_NAME
    Start-PollingServiceStatus -Name $SPARTAN_SERVICE_NAME
    # Point the DNS from the host to the Spartan local DNS
    Set-DnsClientServerAddress -InterfaceAlias * -ServerAddresses @('192.51.100.1', '192.51.100.2', '192.51.100.3')

    # TODO(ibalutoiu): Remove this workaround of stopping/starting the Docker service once the embedded Docker DNS is disabled
    Start-Service "Docker"
}


try {
    New-Environment
    Install-SpartanDevice
    Set-SpartanDevice
    New-SpartanWindowsAgent
    Open-WindowsFirewallRule -Name "Allow inbound TCP Port 53 for Spartan" -Direction "Inbound" -LocalPort 53 -Protocol "TCP"
    Open-WindowsFirewallRule -Name "Allow inbound UDP Port 53 for Spartan" -Direction "Inbound" -LocalPort 53 -Protocol "UDP"
} catch {
    Write-Output $_.ToString()
    exit 1
}
Write-Output "Successfully finished setting up the Windows Spartan Agent"
exit 0
