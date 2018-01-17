## Jenkins CI scripts for Mesos and DC/OS

The current repository contains the necessary scripts to create a Jenkins based CI. It has the following structure:

* `Mesos` - directory with the cron jobs scripts (for checking the pending Mesos review requests and starting the Mesos nightly build), the main Mesos Jenkins jobs scripts and other helper scripts (written Python and PowerShell);
* `Spartan` - directory with the scripts for building and testing Spartan on Windows;
* `DCOS` - directory with the scripts necessary to spawn a [DC/OS](https://dcos.io/) cluster on Azure using [acs-engine](https://github.com/Azure/acs-engine) automation tool. See the README from the DCOS directory for additional information;
* `Modules` - directory with the common PowerShell modules;
* `global-variables.ps1`, PowerShell file with all the global variables. This is sourced on the Windows building nodes when trying to build any of the projects in the CI.
