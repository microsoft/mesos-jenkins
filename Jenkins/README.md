## Jenkins on Docker

This directory contains:

- Docker file (`Dockerfile`) for the Jenkins software container
- Bash scripts to create / restore backups (`restore-backup.sh` and `create-backup.sh`) for the Jenkins software container and the data volume
- Bash script to save the plugins (`save-plugins.sh`) from a Jenkins server to a file
- File with the currently used Jenkins plug-ins (`plugins.txt`)
- PowerShell script (`set-up-windows-jenkins-build-server.ps1`) used to install and configure all the prerequisites for the Jenkins Windows build server
- Bash script to upgrade the Jenkins software container (`upgrade-jenkins.sh`)
