## DC/OS Net on Windows build

This directory contains the scripts used in the Jenkins CI to build [dcos-net](https://github.com/dcos/dcos-net) on Windows.

The main script to build and upload the DC/OS Net build artifacts to the log server is `start-windows-build.ps1`. The requirements for running the script are:

- [OTP 20.2](https://www.erlang.org/downloads/20.3) x64 installed and `$ERLANG_INSTALL_DIR\erts-9.2\bin` added to `$env:PATH`
- [MSYS2](http://www.msys2.org/) x64 installed and `$MSYS2_INSTALL_DIR\usr\bin` added to `$env:PATH`
- [7-Zip](http://www.7-zip.org/download.html) x64 installed and `${env:ProgramFiles}\7-Zip` added to the `$env:PATH`
- `Dig.exe` installed and added to the `$env:PATH`
- `make` tool installed. You can install it via `pacman` (which comes with msys2) by simply running: `pacman -S make`
