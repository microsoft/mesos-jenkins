#### WIP ####
# Windows Mesos Agent build using Jenkins jobs

The scripts are written to be used with Jenkins job in mind. Some variables will be taken from the env, passed down from either gearman or another Jenkins job.

The process can be broken into 3 Jenkins jobs.

First job will handle the Reviewboard polling and getting the patches that need verification.
This is achieved through "files/verify-review-requests.py", a modified version of the original mesos "verify-reviews.py".

    verify-review-requests.py -u $USER -p $PASSWORD -o $OUT_FILE
    
    -u : Reviewboard username
    -p : Reviewboard password
    -o : output file where the patches that need verification are written to
    
For each patch that needs verification, a mesos build job will be started in Jenkins.
The second job runs on a Windows Jenkins slave.
The main script is "windows-slave/start_build.ps1". 
First, all the prerequisite software is checked, and if not found, it is installed. e.g : git, cmake, VS2017 etc.
The env variables used are $branch and $commitid (patchid). The $patchid variable is received from the first job.

Based on these 2 variables, the script behaves a little differently. 
This job can be used to build on master Mesos branch, as well as on stable branches. So based on $branch variable, the mesos repo is pulled and checked out with the specified branch. If no $commitid is given, then most current one will be used. If a patchID is given, then "files/get-reviews-id.py" is used to check for any dependent patches : 
    
    python get-review-ids.py -r $patchid -o $reviewIDsFile
    
    -r : Reviewboard patch ID
    -o : output file to write the dependent patches
    
All the patches from the outputed file will be applied on the most recent master git clone. The "support/apply-reviews.py" from the official Mesos repo is used to apply the patches. The python script must be ran from the repo root, otherwise will fail to apply patch.

    python .\support\apply-reviews.py -n -r $patchid

    -n : no commit message
    -r : Reviewboard patch ID

The next step is to use cmake
Since stable branches use Visual Studio 2015, and master uses Visual Studio 2017, both must be installed on the Windows Jenkins slave. Based on the $branch variable, there are 2 separate commands:
    For master branch:
    cmake "$gitcloneDir" -G "Visual Studio 15 2017 Win64" -T "host=x64" -DENABLE_LIBEVENT=1 -DHAS_AUTHENTICATION=0
    
    For stable branches:
    cmake "$gitcloneDir" -G "Visual Studio 14 2015 Win64" -T "host=x64" -DENABLE_LIBEVENT=1 -DHAS_AUTHENTICATION=0
    
Then we go ahead and build the test suites. There are 3 tests suites : stout-tests, libprocess-tests and mesos-tests

    cmake --build . --target stout-tests --config Debug
    cmake --build . --target libprocess-tests --config Debug
    cmake --build . --target mesos-tests --config Debug
    
After each build, the tests are ran aswell

If all tests pass, the binaries are built and alongside the logs are uploaded onto a webserver.
After the job finishes, be it successfull or failed, a third Jenkins job is triggered.

The third Jenkins job posts back a comment on the Reviewboard on the tested patch, depending on the status of the second build.

    post-build-result.py -u "$USER" -p "$PASSWORD" -r "$patchid" -m "$POST_MESSAGE" -l "$LOGS_URL"
    
    -u : Reviewboard username
    -p : Reviewboard password
    -r : Reviewboard patch ID
    -m : Message to post on the Reviewboard
    -l : The logs URL for the tested patch that will be included into the message posted on the Reviewboard

    
There is also a DCOS folder present in this repo that deploys a DC/OS cluster in Azure using a Linux master and a Windows Mesos agent. For more details check the DCOS directory
