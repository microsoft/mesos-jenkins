## To test manually:
- Create an ftp server to store the `preprovision-agent-windows.ps1` script
- Modify the `apimodel.json` template to point to the ftp server in the `extentionProfiles` section
- Add windows credential to the `apimodel.json` template
- Generate arm template using dcos-engine and deploy the DCOS cluster
- Copy `fluentd.Tests.ps1` and `td-agent.conf` in a directory on the windows hosts
- Run the tests by calling `Invoke-Pester` from Powershell in the same directory
