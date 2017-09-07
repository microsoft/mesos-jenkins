# Mesos configurations
$BOOTSTRAP_TEMP_DIR = Join-Path $env:Temp "DCOS_Bootstrap"
$MESOS_DIR = Join-Path $env:SystemDrive "mesos"
$MESOS_BIN_DIR = Join-Path $MESOS_DIR "bin"
$MESOS_WORK_DIR = Join-Path $MESOS_DIR "work"
$MESOS_LOG_DIR = Join-Path $MESOS_DIR "log"
$MESOS_SERVICE_DIR = Join-Path $MESOS_DIR "service"
$MESOS_BUILD_DIR = Join-Path $MESOS_DIR "build"
$MESOS_SERVICE_NAME = "mesos-agent"
$MESOS_AGENT_PORT = 5051
$MESOS_BINARIES_DIR = Join-Path $MESOS_DIR "binaries"
$MESOS_GIT_REPO_DIR = Join-Path $MESOS_DIR "mesos"
$MESOS_JENKINS_GIT_REPO_DIR = Join-Path $MESOS_DIR "mesos-jenkins"
$MESOS_LOG_SERVER_BASE_URL = "http://dcos-win.westus.cloudapp.azure.com"
$MESOS_BUILD_BASE_URL = "$MESOS_LOG_SERVER_BASE_URL/mesos-build"
$MESOS_BUILD_OUT_DIR = Join-Path $MESOS_DIR "build-output"
$MESOS_BUILD_LOGS_DIR = Join-Path $MESOS_BUILD_OUT_DIR "logs"
$MESOS_BUILD_BINARIES_DIR = Join-Path $MESOS_BUILD_OUT_DIR "dcos-windows"
$ZOOKEEPER_PORT = 2181

# Installers URLs
$SERVICE_WRAPPER_URL = "$MESOS_LOG_SERVER_BASE_URL/downloads/WinSW.NET4.exe"
$VS2017_URL = "https://download.visualstudio.microsoft.com/download/pr/10930949/045b56eb413191d03850ecc425172a7d/vs_Community.exe"
$CMAKE_URL = "https://cmake.org/files/v3.9/cmake-3.9.0-win64-x64.msi"
$GNU_WIN32_URL = "https://10gbps-io.dl.sourceforge.net/project/gnuwin32/patch/2.5.9-7/patch-2.5.9-7-setup.exe"
$GIT_URL = "$MESOS_LOG_SERVER_BASE_URL/downloads/Git-2.14.1-64-bit.exe"
$PYTHON_URL = "https://www.python.org/ftp/python/2.7.13/python-2.7.13.msi"
$PUTTY_URL = "https://the.earth.li/~sgtatham/putty/0.70/w64/putty-64bit-0.70-installer.msi"
$7ZIP_URL = "http://d.7-zip.org/a/7z1700-x64.msi"

# Tools installation directories
$GIT_DIR = Join-Path $env:ProgramFiles "Git"
$CMAKE_DIR = Join-Path $env:ProgramFiles "CMake"
$VS2017_DIR = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\2017\Community"
$GNU_WIN32_DIR = Join-Path ${env:ProgramFiles(x86)} "GnuWin32"
$PYTHON_DIR = Join-Path $env:SystemDrive "Python27"
$PUTTY_DIR = Join-Path $env:ProgramFiles "PuTTY"
$7ZIP_DIR = Join-Path $env:ProgramFiles "7-Zip"

# Git repositories URLs
$MESOS_GIT_URL = "https://github.com/apache/mesos"
$MESOS_JENKINS_GIT_URL = "https://github.com/ionutbalutoiu/mesos-jenkins" # TODO(ibalutoiu): Change it to official repository
$DCOS_WINDOWS_URL = "https://github.com/yakman2020/dcos-windows"

# Remote log server
$REMOTE_LOG_SERVER = "10.3.1.6"
$REMOTE_USER = "logs"
$REMOTE_KEY = Join-Path $env:SystemDrive "jenkins\workspace\key\logs_id_rsa.ppk"
$REMOTE_MESOS_BUILD_DIR = "/data/mesos-build"
