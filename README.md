## Jenkins CI scripts for Mesos and DC/OS

The current repository contains the necessary scripts to create a Jenkins based CI. It has the following structure:

* `DCOS` - scripts and files necessary to do the end-to-end [DC/OS](https://dcos.io/) testing (with Linux and Windows agents) on Azure
* `Diagnostics` - scripts to build, test and package [dcos-diagnostics](https://github.com/dcos/dcos-diagnostics) on Windows
* `Jenkins` - scripts and utilities necessary to set up the [main Jenkins Server](https://mesos-jenkins.westus.cloudapp.azure.com/) and the Jenkins slaves
* `Mesos` - scripts to build, test and package [Mesos](https://github.com/apache/Mesos) on Windows
* `Metrics` - scripts to build, test and package [dcos-metrics](https://github.com/dcos/dcos-metrics) on Windows
* `Spartan`(*deprecated since DC/OS 1.11*) - scripts to build, test and package [dcos-spartan](https://github.com/dcos/spartan) on Windows
* `Net` - scripts to build, test and package [dcos-net](https://github.com/dcos/dcos-net) on Windows
* `Modules` - the common PowerShell modules
* `global-variables.ps1` - PowerShell file with all the global variables
