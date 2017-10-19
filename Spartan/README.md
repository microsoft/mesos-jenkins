## DCOS Spartan Windows agent building

This directory contains the scripts used in the Jenkins CI for building Spartan on Windows.

The main script to build and upload the Spartan build files to the log server is `start-windows-build.ps1`. The requirements for running the script are:

- [Erlang 19](https://www.erlang.org/downloads/19.3).3 x64 installed and `$ERLANG_INSTALL_DIR\erts-8.3\bin` added to `$env:PATH`
- [Mysys2](http://www.msys2.org/) x64 installed and `$MYSYS2_INSTALL_DIR\usr\bin` added to `$env:PATH`
- [7-Zip](http://www.7-zip.org/download.html) x64 installed and `${env:ProgramFiles}\7-Zip` added to the `$env:PATH`
- `make` tool installed. You can install it via `pacman` (which comes with mysys2) by simply running: `pacman -S make`
