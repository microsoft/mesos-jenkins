Param(
)
$ErrorActionPreference = "Stop"

# Source the config and utils scripts.
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\config.ps1"
. "$scriptPath\utils.ps1"

# Check if all requiered services are installed
write-host "Checking prereq software"
invoke-expression -Command $scriptPath\check_prereq.ps1

# Add cmake and git to path
$env:path += ";C:\Program Files\CMake\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\bin;C:\Python27;C:\Python27\Scripts;C:\Program Files\7-Zip;"

# Check and create if the paths are not present
CheckLocalPaths

# Create remote log paths
CreateRemotePaths "$remotelogdirPath" "$remotelogLn"

# Clone the mesos repo
GitClonePull $gitcloneDir $mesos_git_url $branch

# Set the commitID we are working with
# We don't run per commit build yet, just one per day so no commitID is necesarry
#Set-GitCommidID $commitID
#Set-commitInfo

# Set Visual Studio variables based on tested branch
if ($branch -eq "master") {
    Set-VCVars "15.0"
}
else {
    Set-VCVars "14.0"
}

# run config on the repo
pushd $commitbuildDir
if ($branch -eq "master") {
    & cmake "$gitcloneDir" -G "Visual Studio 15 2017 Win64" -T "host=x64" -DENABLE_LIBEVENT=1 -DHAS_AUTHENTICATION=0 | Tee-Object -FilePath "$commitlogDir\make.log"
}
else {
    & cmake "$gitcloneDir" -G "Visual Studio 14 2015 Win64" -T "host=x64" -DENABLE_LIBEVENT=1 -DHAS_AUTHENTICATION=0 | Tee-Object -FilePath "$commitlogDir\make.log"
}
# First we build the tests and run them. If any of the tests fail we abort the build
# Build stout-tests
& cmake --build . --target stout-tests --config Debug | Tee-Object -FilePath "$commitlogDir\build-stout-tests.log"

if ($LastExitCode) {
    write-host "stout-tests failed to build. Logs can be found at $logs_url\$branch\$commitID"
    Copy-RemoteLogs "$commitlogDir\*" "$remotelogdirPath"
    Cleanup
    exit 1
}
write-host "stout-tests finished building"
#Run stout-tests
& .\3rdparty\stout\tests\Debug\stout-tests.exe | Tee-Object -FilePath "$commitlogDir\stout-tests.log"

if ($LastExitCode) {
    write-host "stout-tests have exited with non zero code. Logs can be found at $logs_url\$branch\$commitID"
    Copy-RemoteLogs "$commitlogDir\*" "$remotelogdirPath"
    Cleanup
    exit 1
}
write-host "stout-tests PASSED"
# Build libprocess tests
& cmake --build . --target libprocess-tests --config Debug | Tee-Object -FilePath "$commitlogDir\build-libprocess-tests.log"

if ($LastExitCode) {
    write-host "libprocess-tests failed to build. Logs can be found at $logs_url\$branch\$commitID"
    Copy-RemoteLogs "$commitlogDir\*" "$remotelogdirPath"
    Cleanup
    exit 1
}
write-host "libprocess-tests finished building"
# Run libprocess-tests
& .\3rdparty\libprocess\src\tests\Debug\libprocess-tests.exe | Tee-Object -FilePath "$commitlogDir\libprocess-tests.log"

if ($LastExitCode) {
    write-host "libprocess-tests have exited with non zero code. Logs can be found at $logs_url\$branch\$commitID"
    Copy-RemoteLogs "$commitlogDir\*" "$remotelogdirPath"
    Cleanup
    exit 1
}
write-host "libprocess-tests PASSED"
# Build mesos-tests
& cmake --build . --target mesos-tests --config Debug | Tee-Object -FilePath "$commitlogDir\build-mesos-tests.log"

if ($LastExitCode) {
    write-host "mesos-tests failed to build. Logs can be found at $logs_url\$branch\$commitID"
    Copy-RemoteLogs "$commitlogDir\*" "$remotelogdirPath"
    Cleanup
    exit 1
}
write-host "mesos-tests finished building"
# Run mesos-tests. These tests must be run with administrator priviliges
& .\src\mesos-tests.exe --verbose | Tee-Object -FilePath "$commitlogDir\mesos-tests.log"

if ($LastExitCode) {
    write-host "mesos-tests have exited with non zero code. Logs can be found at $logs_url\$branch\$commitID"
    Copy-RemoteLogs "$commitlogDir\*" "$remotelogdirPath"
    Cleanup
    exit 1
}
write-host "mesos-tests PASSED"

# After the tests finished and all PASSED is time to build the mesos binaries
write-host "Started building mesos binaries"
& cmake --build . | Tee-Object -FilePath "$commitlogDir\mesos-build.log"

if ($LastExitCode) {
    write-host "Something went wrong with building the binaries. Logs can be found at $logs_url\$branch\$commitID"
    Copy-RemoteLogs "$commitlogDir\*" "$remotelogdirPath"
    Cleanup
    exit 1
}
write-host "Finished building mesos binaries"
popd

# Copy binaries to a store location and archive them
CopyLocalBinaries "$commitbuildDir\src" "$commitbinariesDir"
CompressBinaries "$commitbinariesDir" "$commitbinariesDir\binaries-$commitID.zip"
CompressPDB "$commitbinariesDir" "$commitbinariesDir\pdb-$commitID.zip"

# Copy logs and binaries to the remote location
write-host "Copying logs to remote log server"
Copy-RemoteLogs "$commitlogDir\*" "$remotelogdirPath"
write-host "Logs can be found at $logs_url\$branch\$commitID"
write-host "Copying binaries to remote server"
CreateRemotePaths "$remotebinariesdirPath" "$remotebinariesLn"
Copy-RemoteBinaries "$commitbinariesDir\*" "$remotebinariesdirPath"
write-host "Binaries can be found at $binaries_url\$branch\$commitID"

# Cleanup env
Cleanup
