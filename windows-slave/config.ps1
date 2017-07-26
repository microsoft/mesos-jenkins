# env variables
#$commitID = $env:commitid
# First we will build once per day and not per commit, so the commitID will be a timestamp for the folder naming
$commitID = (get-date -f hh_mm-yyyy_MM_dd)

# Path variables
$baseDir = "C:\mesos"
$buildDir = "$baseDir\build"
$commitDir = "$buildDir\$commitID"
$commitbuildDir = "$commitDir\build"
$binariesDir = "$baseDir\binaries"
$commitbinariesDir = "$binariesDir\$commitID"
$logDir = "$baseDir\logs"
$commitlogDir = "$logDir\$commitID"
$gitclonedir = "$commitDir\mesos"
$tempDir = $env:temp


$git_path = "C:\Program Files\Git"
$cmake_path = "C:\Program Files\CMake"
$vs2017_path = "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community"
$gnu_path = "C:\Program Files (x86)\GnuWin32"
$python_path = "C:\Python27"

# Installer URLs
$vs2017_url = "https://download.visualstudio.microsoft.com/download/pr/10930949/045b56eb413191d03850ecc425172a7d/vs_Community.exe"
$cmake_url = "https://cmake.org/files/v3.9/cmake-3.9.0-win64-x64.msi"
$gnu_url = "https://10gbps-io.dl.sourceforge.net/project/gnuwin32/patch/2.5.9-7/patch-2.5.9-7-setup.exe"
$git_url = "https://github-production-release-asset-2e65be.s3.amazonaws.com/23216272/f77e496e-67d6-11e7-8886-19ce9e1da69a?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIWNJYAX4CSVEH53A%2F20170724%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20170724T094140Z&X-Amz-Expires=300&X-Amz-Signature=c7e416b7893f650e2ed4bac5e37b4be0067fe5e75388f653a57fce67302d5eee&X-Amz-SignedHeaders=host&actor_id=15943551&response-content-disposition=attachment%3B%20filename%3DGit-2.13.3-64-bit.exe&response-content-type=application%2Foctet-stream"
$python_url = "https://www.python.org/ftp/python/2.7.13/python-2.7.13.msi"

# Git url
$mesos_git_url = "https://github.com/apache/mesos"
