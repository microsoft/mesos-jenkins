# Source the config and utils scripts.
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\config.ps1"
. "$scriptPath\utils.ps1"

$has_git = Test-Path -Path $git_path
$has_vs2017 = Test-Path -Path $vs2017_path
$has_gnu = Test-Path -Path $gnu_path
$has_python = Test-Path -Path $python_path
$has_cmake = Test-Path -Path $cmake_path
$has_putty = Test-Path -Path $putty_path
$has_7zip = Test-Path -Path $7zip_path

if (! $has_git) {
    write-host "No git installation detected. Will install"
    write-host "Downloading installer"
    Invoke-WebRequest -UseBasicParsing -Uri $git_url -OutFile "$tempDir\git.exe"
    write-host "Installing git"
    Start-Process -FilePath $tempDir\git.exe -ArgumentList "/SILENT" -Wait -PassThru
}

if (! $has_cmake) {
    write-host "No cmake installation detected. Will install"
    write-host "Downloading installer"
    Invoke-WebRequest -UseBasicParsing -Uri $cmake_url -OutFile "$tempDir\cmake.msi"
    write-host "installing cmake"
    Start-Process -FilePath msiexec.exe -ArgumentList "/quiet","/i","$tempDir\cmake.msi" -Wait -PassThru
}
if (! $has_gnu) {
    write-host "No gnuwin32 installation detected. Will install"
    write-host "Downloading installer"
    Invoke-WebRequest -UseBasicParsing -Uri $gnu_url -OutFile "$tempDir\gnu.exe"
    write-host "Installing gnuwin32"
    Start-Process -FilePath $tempDir\gnu.exe -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/SP-" -Wait -PassThru
}

if (! $has_python) {
    write-host "No python installation detecte. Will install"
    write-host "Downloading installer"
    Invoke-WebRequest -UseBasicParsing -Uri $python_url -OutFile "$tempDir\python27.msi"
    write-host "Installing python"
    Start-Process -FilePath msiexec.exe -ArgumentList "/qn","/i","$tempDir\python27.msi" -Wait -PassThru  #"/ALLUSERS=1",
}

if (! $has_putty) {
    write-host "No putty installation detecte. Will install"
    write-host "Downloading installer"
    Invoke-WebRequest -UseBasicParsing -Uri $putty_url -OutFile "$tempDir\putty.msi"
    write-host "Installing putty"
    Start-Process -FilePath msiexec.exe -ArgumentList "/q","/i","$tempDir\putty.msi" -Wait -PassThru
}

if (! $has_7zip) {
    write-host "No 7zip installation detecte. Will install"
    write-host "Downloading installer"
    Invoke-WebRequest -UseBasicParsing -Uri $7zip_url -OutFile "$tempDir\7zip.msi"
    write-host "Installing 7zip"
    Start-Process -FilePath msiexec.exe -ArgumentList "/q","/i","$tempDir\7zip.msi" -Wait -PassThru
}

if (! $has_vs2017) {
    write-host "No Visual Studio 2017 Community Edition installation detected. Will install"
    write-host "Downloading installer"
    Invoke-WebRequest -UseBasicParsing -Uri $vs2017_url -OutFile "$tempDir\vs2017.exe"
    write-host "Installing Visual Studio 2017 Community Edition"
    Start-Process -FilePath $tempDir\vs2017.exe -ArgumentList "--quiet","--add Microsoft.VisualStudio.Component.CoreEditor","--add Microsoft.VisualStudio.Workload.NativeDesktop","--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64","--add Microsoft.VisualStudio.Component.VC.DiagnosticTools","--add Microsoft.VisualStudio.Component.Windows10SDK.15063.Desktop","--add Microsoft.VisualStudio.Component.VC.CMake.Project","-add Microsoft.VisualStudio.Component.VC.ATL" -Wait -PassThru
}