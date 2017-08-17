This scripts are used in a Jenkins job to spawn a DC/OS environment in Azure. This is a work in progress!
For now a Linux master node and a Windows Mesos agent are built.

You need Azure CLI 2.0 on the Jenkins node that the job runs on.

This job should be run after the mesos-build one, and takes as a Jenkins environment parameters the patch ID tested in the upstream job.

The build_env.sh script is the job itself. 
It logs in to azure using the azure cli, creates a resource group based on the patch ID and then deploys the "templates/azuredeploy.json" using as paramter file the "templates/azuredeploy.parameters.json" that is rendered with the correct variables prior to launch.
After the environment is deployed and ready, 3 Azure compute extensions are created.
The first one uses the Ansible powershell script to enable WinRM on the Windows agent node.
The second one, "prepare-system", installs git, clones this repo and downloads the Mesos binaries on local disk under "C:\mesos\bin". Also, port 5051 is opened on the firewall for the Mesos master to be able to communicate with the Mesos agent.
The third and final extension is "start-mesos-agent". This script uses WinSW wrapper to create a Windows service for the mesos-agent.exe and then starts the agent.

This is as far as it gets with these scripts. In the future we will need to run some tests like spawning a container from DC/OS, etc.