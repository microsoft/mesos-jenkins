Param(
)
$ErrorActionPreference = "Stop"

# Source the config and utils scripts.
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\config.ps1"
. "$scriptPath\utils.ps1"

$has_git = Test-Path -Path $git_path
$has_vs2017 = Test-Path -Path $vs2017_path
$has_gnu = Test-Path -Path $gnu_path
$has_python = Test-Path -Path $python_path
$has_cmake = Test-Path -Path $cmake_path

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

if (! $has_vs2017) {
    write-host "No Visual Studio 2017 Community Edition installation detected. Will install"
    write-host "Downloading installer"
    Invoke-WebRequest -UseBasicParsing -Uri $vs2017_url -OutFile "$tempDir\vs2017.exe"
    write-host "Installing Visual Studio 2017 Community Edition"
    Start-Process -FilePath $tempDir\vs2017.exe -ArgumentList "--quiet","--norestart","--add Microsoft.VisualStudio.Workload.NativeDesktop","--add Microsoft.VisualStudio.ComponentGroup.NativeDesktop.Core","--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64","--add Microsoft.VisualStudio.Component.VC.DiagnosticTools","--add Microsoft.VisualStudio.Component.Windows10SDK.15063.Desktop","--add Microsoft.VisualStudio.Component.VC.CMake.Project","-add Microsoft.VisualStudio.Component.VC.ATL" -Wait -PassThru
}

# Add cmake and git to path
$env:path += ";C:\Program Files\CMake\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\bin;C:\Python27;C:\Python27\Scripts"

# Check and create if the paths are not present
CheckLocalPaths

# Clone the mesos repo
GitClonePull $gitcloneDir $mesos_git_url

# Set the commitID we are working with
# We don't yet run per commit build, just one per day so no commitID is necesarry
#Set-GitCommidID $commitID
#Set-commitInfo

# run config on the repo
pushd $commitbuildDir
& cmake "$gitcloneDir" -G "Visual Studio 15 2017 Win64" -T "host=x64" -DENABLE_LIBEVENT=1 -DHAS_AUTHENTICATION=0 | Tee-Object -FilePath "$commitlogDir\make.log"

# First we build the tests and run them. If any of the tests fail we abort the build
# Build stout-tests
& cmake --build . --target stout-tests --config Debug | Tee-Object -FilePath "$commitlogDir\build-stout-tests.log"

if ($LastExitCode) {
    write-host "stout-tests failed to build. Logs can be found at $commitlogDir\build-stout-tests.log"
    Cleanup
    exit 1
}
write-host "stout-tests finished building"
#Run stout-tests
& .\3rdparty\stout\tests\Debug\stout-tests.exe | Tee-Object -FilePath "$commitlogDir\stout-tests.log"

if ($LastExitCode) {
    write-host "stout-tests have exited with non zero code. Logs can be found at $commitlogDir\stout-tests.log"
    Cleanup
    exit 1
}
write-host "stout-tests PASSED"
# Build libprocess tests
& cmake --build . --target libprocess-tests --config Debug | Tee-Object -FilePath "$commitlogDir\build-libprocess-tests.log"

if ($LastExitCode) {
    write-host "libprocess-tests failed to build. Logs can be found at $commitlogDir\build-libprocess-tests.log"
    Cleanup
    exit 1
}
write-host "libprocess-tests finished building"
# Run libprocess-tests
& .\3rdparty\libprocess\src\tests\Debug\libprocess-tests.exe | Tee-Object -FilePath "$commitlogDir\libprocess-tests.log"

if ($LastExitCode) {
    write-host "libprocess-tests have exited with non zero code. Logs can be found at $commitlogDir\libprocess-tests.log"
    Cleanup
    exit 1
}
write-host "libprocess-tests PASSED"
# Build mesos-tests
& cmake --build . --target mesos-tests --config Debug | Tee-Object -FilePath "$commitlogDir\build-mesos-tests.log"

if ($LastExitCode) {
    write-host "mesos-tests failed to build. Logs can be found at $commitlogDir\build-mesos-tests.log"
    Cleanup
    exit 1
}
write-host "mesos-tests finished building"
# Run mesos-tests. These tests must be run with administrator priviliges
& .\src\mesos-tests.exe --verbose | Tee-Object -FilePath "$commitlogDir\mesos-tests.log"

if ($LastExitCode) {
    write-host "mesos-tests have exited with non zero code. Logs can be found at $commitlogDir\mesos-tests.log"
    Cleanup
    exit 1
}
write-host "mesos-tests PASSED"

# After the tests finished and all PASSED is time to build the mesos binaries
write-host "Started building mesos binaries"
& cmake --build . | Tee-Object -FilePath "$commitlogDir\mesos-build.log"

if ($LastExitCode) {
    write-host "Something went wrong with building the binaries. Logs can be found at $commitlogDir\mesos-build.log"
    Cleanup
    exit 1
}
write-host "Finished building mesos binaries"
popd

# Copy binaries to a store location
CopyBinaries

# Cleanup env
Cleanup
