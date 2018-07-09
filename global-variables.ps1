# DCOS common configurations
$STORAGE_SERVER_ADDRESS = "dcos-win.westus.cloudapp.azure.com"
$STORAGE_SERVER_USER = "jenkins"
$STORAGE_SERVER_BASE_URL = "http://dcos-win.westus.cloudapp.azure.com"
$ARTIFACTS_DIRECTORY = "/storage/data/artifacts"
$ARTIFACTS_BASE_URL = "${STORAGE_SERVER_BASE_URL}/artifacts"
$DCOS_DIR = Join-Path "D:" "DCOS"

# Mesos configurations
$MESOS_DIR = Join-Path $DCOS_DIR "mesos"
$MESOS_GIT_REPO_DIR = Join-Path $MESOS_DIR "mesos"
$MESOS_BUILD_OUT_DIR = Join-Path $MESOS_DIR "build-output"
$MESOS_BUILD_LOGS_DIR = Join-Path $MESOS_BUILD_OUT_DIR "logs"
$MESOS_BUILD_BINARIES_DIR = Join-Path $MESOS_BUILD_OUT_DIR "binaries"

# Spartan configurations
$SPARTAN_DIR = Join-Path $DCOS_DIR "spartan"
$SPARTAN_GIT_REPO_DIR = Join-Path $SPARTAN_DIR "spartan"
$SPARTAN_BUILD_OUT_DIR = Join-Path $SPARTAN_DIR "build-output"
$SPARTAN_RELEASE_DIR = Join-Path $SPARTAN_BUILD_OUT_DIR "release"
$SPARTAN_BUILD_LOGS_DIR = Join-Path $SPARTAN_BUILD_OUT_DIR "logs"

# dcos-net configurations
$DCOS_NET_DIR = Join-Path $DCOS_DIR "dcos-net"
$DCOS_NET_GIT_REPO_DIR = Join-Path $DCOS_NET_DIR "dcos-net"
$DCOS_NET_LIBSODIUM_GIT_DIR = Join-Path $DCOS_NET_DIR "libsodium"
$DCOS_NET_BUILD_OUT_DIR = Join-Path $DCOS_NET_DIR "build-output"
$DCOS_NET_BUILD_RELEASE_DIR = Join-Path $DCOS_NET_BUILD_OUT_DIR "release"
$DCOS_NET_BUILD_LOGS_DIR = Join-Path $DCOS_NET_BUILD_OUT_DIR "logs"

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

# Installers & git repositories URLs
$GIT_URL = "$STORAGE_SERVER_BASE_URL/downloads/git-64-bit.exe"
$7ZIP_URL = "http://d.7-zip.org/a/7z1700-x64.msi"
$GOLANG_URL = "https://dl.google.com/go/go1.9.4.windows-amd64.msi"
$DCOS_WINDOWS_GIT_URL = "https://github.com/dcos/dcos-windows"
$LIBSODIUM_GIT_URL = "https://github.com/jedisct1/libsodium"

# Tools installation directories
$GIT_DIR = Join-Path $env:ProgramFiles "Git"
$7ZIP_DIR = Join-Path $env:ProgramFiles "7-Zip"
$GOLANG_DIR = Join-Path $env:SystemDrive "Go"
