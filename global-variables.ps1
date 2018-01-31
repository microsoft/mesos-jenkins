$JENKINS_SERVER_URL="https://mesos-jenkins.westus.cloudapp.azure.com:8443"

# Remote log server
$REMOTE_LOG_SERVER = "10.3.1.6"
$REMOTE_USER = "logs"
$REMOTE_KEY = Join-Path $env:SystemDrive "jenkins\workspace\key\logs_id_rsa.ppk"
$REMOTE_MESOS_BUILD_DIR = "/data/mesos-build"
$REMOTE_SPARTAN_BUILD_DIR = "/data/spartan-build"

# DCOS common configurations
$LOG_SERVER_BASE_URL = "http://dcos-win.westus.cloudapp.azure.com"
$ERLANG_URL = "$LOG_SERVER_BASE_URL/downloads/erl8.3.zip"
$ZOOKEEPER_PORT = 2181
$EXHIBITOR_PORT = 8181
$DCOS_DIR = Join-Path "D:" "DCOS"
$ERLANG_DIR = Join-Path $DCOS_DIR "erl8.3"
$ERTS_DIR = Join-Path $ERLANG_DIR "erts-8.3"

# Mesos configurations
$MESOS_SERVICE_NAME = "dcos-mesos-slave"
$MESOS_AGENT_PORT = 5051
$MESOS_DIR = Join-Path $DCOS_DIR "mesos"
$MESOS_BIN_DIR = Join-Path $MESOS_DIR "bin"
$MESOS_WORK_DIR = Join-Path $MESOS_DIR "work"
$MESOS_LOG_DIR = Join-Path $MESOS_DIR "log"
$MESOS_SERVICE_DIR = Join-Path $MESOS_DIR "service"
$MESOS_BUILD_DIR = Join-Path $MESOS_DIR "build"
$MESOS_BINARIES_DIR = Join-Path $MESOS_DIR "binaries"
$MESOS_GIT_REPO_DIR = Join-Path $MESOS_DIR "mesos"
$MESOS_BUILD_OUT_DIR = Join-Path $MESOS_DIR "build-output"
$MESOS_BUILD_LOGS_DIR = Join-Path $MESOS_BUILD_OUT_DIR "logs"
$MESOS_BUILD_BINARIES_DIR = Join-Path $MESOS_BUILD_OUT_DIR "binaries"
$MESOS_BUILD_BASE_URL = "$LOG_SERVER_BASE_URL/mesos-build"

# EPMD configurations
$EPMD_SERVICE_NAME = "dcos-epmd"
$EPMD_PORT = 61420
$EPMD_DIR = Join-Path $DCOS_DIR "epmd"
$EPMD_SERVICE_DIR = Join-Path $EPMD_DIR "service"
$EPMD_LOG_DIR = Join-Path $EPMD_DIR "log"

# Spartan configurations
$SPARTAN_SERVICE_NAME = "dcos-spartan"
$SPARTAN_DEVICE_NAME = "spartan"
$SPARTAN_DIR = Join-Path $DCOS_DIR "spartan"
$SPARTAN_RELEASE_DIR = Join-Path $SPARTAN_DIR "release"
$SPARTAN_LOG_DIR = Join-Path $SPARTAN_DIR "log"
$SPARTAN_SERVICE_DIR = Join-Path $SPARTAN_DIR "service"
$SPARTAN_GIT_REPO_DIR = Join-Path $SPARTAN_DIR "spartan"
$SPARTAN_BUILD_OUT_DIR = Join-Path $SPARTAN_DIR "build-output"
$SPARTAN_BUILD_LOGS_DIR = Join-Path $SPARTAN_BUILD_OUT_DIR "logs"
$SPARTAN_BUILD_BASE_URL = "$LOG_SERVER_BASE_URL/spartan-build"

# Installers URLs
$SERVICE_WRAPPER_URL = "$LOG_SERVER_BASE_URL/downloads/WinSW.NET4.exe"
$VS2017_URL = "https://download.visualstudio.microsoft.com/download/pr/10930949/045b56eb413191d03850ecc425172a7d/vs_Community.exe"
$CMAKE_URL = "https://cmake.org/files/v3.9/cmake-3.9.0-win64-x64.msi"
$GNU_WIN32_URL = "https://10gbps-io.dl.sourceforge.net/project/gnuwin32/patch/2.5.9-7/patch-2.5.9-7-setup.exe"
$GIT_URL = "$LOG_SERVER_BASE_URL/downloads/Git-2.14.1-64-bit.exe"
$PYTHON_URL = "https://www.python.org/ftp/python/2.7.13/python-2.7.13.msi"
$PUTTY_URL = "https://the.earth.li/~sgtatham/putty/0.70/w64/putty-64bit-0.70-installer.msi"
$7ZIP_URL = "http://d.7-zip.org/a/7z1700-x64.msi"
$VCREDIST_2013_URL = "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe"
$DEVCON_CAB_URL = "https://download.microsoft.com/download/7/D/D/7DD48DE6-8BDA-47C0-854A-539A800FAA90/wdk/Installers/787bee96dbd26371076b37b13c405890.cab"

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
$SPARTAN_GIT_URL = "https://github.com/dcos/spartan"
