# Remote log server
$REMOTE_MESOS_BUILD_DIR = "/data/mesos-build"
$REMOTE_SPARTAN_BUILD_DIR = "/data/spartan-build"
$REMOTE_DCOS_NET_BUILD_DIR = "/data/net-build"

# DCOS common configurations
$STORAGE_SERVER_ADDRESS = "dcos-win.westus.cloudapp.azure.com"
$STORAGE_SERVER_USER = "jenkins"
$STORAGE_SERVER_BASE_URL = "http://dcos-win.westus.cloudapp.azure.com"
$ARTIFACTS_DIRECTORY = "/storage/data/artifacts"
$ARTIFACTS_BASE_URL = "${STORAGE_SERVICE_BASE_URL}/artifacts"
$ZOOKEEPER_PORT = 2181
$EXHIBITOR_PORT = 8181
$DCOS_DIR = Join-Path "D:" "DCOS"
$ERLANG_URL = "$STORAGE_SERVER_BASE_URL/downloads/erl8.3.zip"
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
$MESOS_BUILD_BASE_URL = "$STORAGE_SERVER_BASE_URL/mesos-build"

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
$SPARTAN_BUILD_BASE_URL = "$STORAGE_SERVER_BASE_URL/spartan-build"

# dcos-net configurations
$DCOS_NET_SERVICE_NAME = "dcos-net"
$DCOS_NET_DIR = Join-Path $DCOS_DIR "dcos-net"
$DCOS_NET_GIT_REPO_DIR = Join-Path $DCOS_NET_DIR "dcos-net"
$DCOS_NET_LIBSODIUM_GIT_DIR = Join-Path $DCOS_NET_DIR "libsodium"
$DCOS_NET_BUILD_OUT_DIR = Join-Path $DCOS_NET_DIR "build-output"
$DCOS_NET_BUILD_RELEASE_DIR = Join-Path $DCOS_NET_BUILD_OUT_DIR "release"
$DCOS_NET_BUILD_LOGS_DIR = Join-Path $DCOS_NET_BUILD_OUT_DIR "logs"
$DCOS_NET_BUILD_BASE_URL = "$STORAGE_SERVER_BASE_URL/net-build"

# Diagnostics configurations
$DIAGNOSTICS_DIR = Join-Path $DCOS_DIR "diagnostics"
$DIAGNOSTICS_GIT_REPO_DIR = Join-Path $DIAGNOSTICS_DIR "src\github.com\dcos\dcos-diagnostics"
$DIAGNOSTICS_BUILD_OUT_DIR = Join-Path $DIAGNOSTICS_DIR "build-output"
$DIAGNOSTICS_BUILD_LOGS_DIR = Join-Path $DIAGNOSTICS_BUILD_OUT_DIR "logs"
$DIAGNOSTICS_BUILD_BINARIES_DIR = Join-Path $DIAGNOSTICS_BUILD_OUT_DIR "binaries"

# Metrics configurations
$METRICS_DIR = Join-Path $DCOS_DIR "metrics"
$METRICS_GIT_REPO_DIR = Join-Path $METRICS_DIR "src\github.com\dcos\dcos-metrics"
$METRICS_BUILD_OUT_DIR = Join-Path $METRICS_DIR "build-output"
$METRICS_BUILD_LOGS_DIR = Join-Path $METRICS_BUILD_OUT_DIR "logs"
$METRICS_BUILD_BINARIES_DIR = Join-Path $METRICS_BUILD_OUT_DIR "binaries"
$METRICS_DCOS_WINDOWS_GIT_REPO_DIR = Join-Path $METRICS_DIR "dcos-windows"
$METRICS_MESOS_JENKINS_GIT_REPO_DIR = Join-Path $METRICS_DIR "mesos-jenkins"

# Installers & git repositories URLs
$GIT_URL = "$STORAGE_SERVER_BASE_URL/downloads/git-64-bit.exe"
$7ZIP_URL = "http://d.7-zip.org/a/7z1700-x64.msi"
$GOLANG_URL = "https://dl.google.com/go/go1.9.4.windows-amd64.msi"
$DCOS_WINDOWS_GIT_URL = "https://github.com/dcos/dcos-windows"
$MESOS_JENKINS_GIT_URL = "https://github.com/Microsoft/mesos-jenkins"
$LIBSODIUM_GIT_URL = "https://github.com/jedisct1/libsodium"

# Tools installation directories
$GIT_DIR = Join-Path $env:ProgramFiles "Git"
$7ZIP_DIR = Join-Path $env:ProgramFiles "7-Zip"
$GOLANG_DIR = Join-Path $env:SystemDrive "Go"
