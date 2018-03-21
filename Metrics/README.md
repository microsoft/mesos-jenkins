## Metrics Windows agent building and testing

These scripts are written to be used as [Jenkins](https://jenkins.io/) jobs in an automated CI. Some variables will be taken from the `$env`, passed down from either a [Gearman](http://gearman.org/) or another upstream Jenkins job.

The process of testing the Metrics builds is done with the `start-windows-build.ps1` script and it can be broken into the following parts:

* Install all the prerequisites necessary for the Windows Metrics build: Golang, git, and 7Zip
* Create a new tests environment. At this step, the build directories are created and the three git repositories are clone (dcos-metrics, dcos-windows, and mesos-jenkins). 
All repos are synced to the latest commit on master branch;
* Build Metrics
* Build and run Metrics unittests
* Create/Copy config files for the metrics service
* Compress above files into a metrics.zip

At the end of any Metrics build (it doesn't matter if it was successful or not), all the build artifacts (logs and possible binaries) are uploaded to a separate log server.
