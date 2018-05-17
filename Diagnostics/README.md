## Diagnostics Windows agent building and testing

The process of testing the Diagnostics builds is done with the `start-windows-build.ps1` script and it can be broken into the following parts:

* Install all the prerequisites necessary for the Windows Diagnostics build: Golang, git, and 7Zip
* Create a new tests environment. At this step, the build directories are created and the three git repositories are clone (dcos-diagnostics, dcos-windows, and mesos-jenkins). 
All repos are synced to the latest commit on master branch;
* Build Diagnostics
* Build and run Diagnostics unittests
* Create/Copy config files for the diagnostics service
* Compress above files into a diagnostics.zip

At the end of any Diagnostics build (it doesn't matter if it was successful or not), all the build artifacts (logs and possible binaries) are uploaded to a separate log server.
