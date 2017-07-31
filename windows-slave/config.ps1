# env variables
#$commitID = $env:commitid
# First we will build once per day and not per commit, so the commitID will be a timestamp for the folder naming
$commitID = (get-date -f dd_MM_yyyy-hh_mm)
$branch = $env:branch
$is_debug = $env:debug

# Path variables
$baseDir = "C:\mesos"
$buildDir = "$baseDir\build"
$commitDir = "$buildDir\$branch\$commitID"
$commitbuildDir = "$commitDir\build"
$binariesDir = "$baseDir\binaries"
$commitbinariesDir = "$binariesDir\$branch\$commitID"
$logDir = "$baseDir\logs"
$commitlogDir = "$logDir\$branch\$commitID"
$gitclonedir = "$commitDir\mesos"
$tempDir = $env:temp


$git_path = "C:\Program Files\Git"
$cmake_path = "C:\Program Files\CMake"
$vs2017_path = "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community"
$gnu_path = "C:\Program Files (x86)\GnuWin32"
$python_path = "C:\Python27"
$putty_path = "C:\Program Files\PuTTY"
$7zip_path = "C:\Program Files\7-Zip"

# Installer URLs
$vs2017_url = "https://download.visualstudio.microsoft.com/download/pr/10930949/045b56eb413191d03850ecc425172a7d/vs_Community.exe"
$cmake_url = "https://cmake.org/files/v3.9/cmake-3.9.0-win64-x64.msi"
$gnu_url = "https://10gbps-io.dl.sourceforge.net/project/gnuwin32/patch/2.5.9-7/patch-2.5.9-7-setup.exe"
$git_url = "http://81.181.181.155:8081/shared/kits/Git-2.13.2-64-bit.exe"
$python_url = "https://www.python.org/ftp/python/2.7.13/python-2.7.13.msi"
$putty_url = "https://the.earth.li/~sgtatham/putty/0.70/w64/putty-64bit-0.70-installer.msi"
$7zip_url = "http://d.7-zip.org/a/7z1700-x64.msi"

# Git url
$mesos_git_url = "https://github.com/apache/mesos"

# Remote log server
$remoteServer = "10.3.1.6"
$remoteUser = "logs"
$remoteKey = "C:\mesos\key\logs_id_rsa.ppk"
$remotelogDir = "/data/logs"
$remotebinariesDir = "/data/binaries"
$remotelogdirPath = "$remotelogDir/$branch/$commitID"
$remotebinariesdirPath = "$remotebinariesDir/$branch/$commitID"
$remotelogLn = "$remotelogDir/$branch/latest"
$remotebinariesLn = "$remotebinariesDir/$branch/latest"
$logs_url = "http://104.210.40.105/logs"
$binaries_url = "http://104.210.40.105/binaries"
