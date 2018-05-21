## Mesos Windows agent building and testing

The process of testing the Mesos builds is done with the `start-windows-build.ps1` script and it can be broken into the following parts:

* Install all the prerequisites necessary for the Windows Mesos build;
* Create a new tests environment. At this step, the build directories are created and the Mesos git repository is cloned. If the `start-windows-build.ps1` receives the `$CommitID` parameter, then the Mesos latest commit is set to that one. In addition to that, if `$ReviewID` parameter is passed as well, the pending review request is applied locally, together with all the dependent review requests;
* Build Mesos;
* Build and run the Mesos `stout-tests` unit tests;
* Build and run the Mesos `libprocess-tests` unit tests;
* Build and run the Mesos `mesos-tests` unit tests;
* If no error has occurred until this step, then the Mesos binaries are generated and we successfully finish testing the current Mesos build.

At the end of any Mesos build (it doesn't matter if it was successful or not), all the build artifacts (logs and possible binaries) are uploaded to a separate log server.
