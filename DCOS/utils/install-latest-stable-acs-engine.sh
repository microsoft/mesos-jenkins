#!/usr/bin/env bash
set -e

REPO_URL="https://github.com/Azure/acs-engine"
REPO_DIR="/tmp/acs-engine"

# Get the current ACS Engine (or set the variable to "" if the acs-engine is not installed)
which acs-engine > /dev/null && ACS_VERSION=$(acs-engine version | grep "Version" | awk '{print $2}') || ACS_VERSION=""

if [[ $ACS_VERSION != "" ]]; then
    echo "Detected installed ACS Engine version: $ACS_VERSION"
    rm -rf $REPO_DIR
    echo "Checking if there is a newer stable ACS Engine"
    git clone $REPO_URL $REPO_DIR &> /dev/null
    pushd $REPO_DIR &> /dev/null
    ACS_LATEST_STABLE_VERSION=$(git tag --sort=-taggerdate | head -1)
    popd &> /dev/null
    rm -rf $REPO_DIR
    if [[ "$ACS_VERSION" = "$ACS_LATEST_STABLE_VERSION" ]]; then
        echo "ACS Engine is already updated to the latest stable version: $ACS_VERSION"
        exit 0
    fi
    echo "New ACS Engine version available: $ACS_LATEST_STABLE_VERSION"
fi

echo "Installing ACS Engine latest stable"

export GOPATH="/tmp/golang"
export PATH="$PATH:/usr/local/go/bin:$GOPATH/bin"

go get -v github.com/Azure/acs-engine

pushd $GOPATH/src/github.com/Azure/acs-engine
if [[ -z $ACS_LATEST_STABLE_VERSION ]]; then
    ACS_LATEST_STABLE_VERSION=$(git tag --sort=-taggerdate | head -1)
fi
git checkout $ACS_LATEST_STABLE_VERSION
make bootstrap
make build
sudo mv ./bin/acs-engine /usr/local/bin/acs-engine
popd
rm -rf $GOPATH

echo "Finished installing ACS Engine version: $ACS_LATEST_STABLE_VERSION"
