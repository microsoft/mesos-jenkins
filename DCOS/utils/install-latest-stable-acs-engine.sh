#!/usr/bin/env bash
set -e

REPO_URL="https://github.com/Azure/acs-engine"
REPO_DIR="$WORKSPACE/acs-engine"
GIT_RELEASE_BASE_URL="https://github.com/Azure/acs-engine/releases/download"

# Get the current ACS Engine (or set the variable to "" if the acs-engine is not installed)
which acs-engine > /dev/null && ACS_VERSION=$(acs-engine version | grep "Version" | awk '{print $2}') || ACS_VERSION=""

rm -rf $REPO_DIR
git clone $REPO_URL $REPO_DIR
pushd $REPO_DIR

if [[ $ACS_VERSION != "" ]]; then
    echo "Detected installed ACS Engine version: $ACS_VERSION. Checking if there is a newer stable ACS Engine"
    ACS_LATEST_STABLE_VERSION=$(git tag --sort=committerdate | tail -1)
    if [[ "$ACS_VERSION" = "$ACS_LATEST_STABLE_VERSION" ]]; then
        echo "ACS Engine is already updated to the latest stable version: $ACS_VERSION"
        popd
        rm -rf $REPO_DIR
        exit 0
    fi
    echo "New ACS Engine version available: $ACS_LATEST_STABLE_VERSION"
fi

echo "Installing ACS Engine latest stable"

if [[ -z $ACS_LATEST_STABLE_VERSION ]]; then
    ACS_LATEST_STABLE_VERSION=$(git tag --sort=committerdate | tail -1)
fi
popd
rm -rf $REPO_DIR

RELEASE_URL="${GIT_RELEASE_BASE_URL}/${ACS_LATEST_STABLE_VERSION}/acs-engine-${ACS_LATEST_STABLE_VERSION}-linux-amd64.tar.gz"
OUT_FILE="acs-engine-${ACS_LATEST_STABLE_VERSION}-linux-amd64.tar.gz"

cd $WORKSPACE
EXIT_CODE=0
OUTPUT=$(wget $RELEASE_URL -O $OUT_FILE 2>&1) || EXIT_CODE=1
if [[ $EXIT_CODE -ne 0 ]]; then
    if echo $OUTPUT | grep -q "ERROR 404"; then
        echo "There isn't a git download URL for the new version: $ACS_LATEST_STABLE_VERSION. Will still use ACS Engine version: $ACS_VERSION"
        exit 0
    else
        echo $OUTPUT
        exit 1
    fi
fi

tar xzf $OUT_FILE
EXTRACT_DIR="acs-engine-${ACS_LATEST_STABLE_VERSION}-linux-amd64"
mkdir -p $WORKSPACE/bin
export PATH="$WORKSPACE/bin:$PATH"
mv $EXTRACT_DIR/acs-engine $WORKSPACE/bin/acs-engine
chmod +x $WORKSPACE/bin/acs-engine
rm -rf $EXTRACT_DIR $OUT_FILE

echo "Finished installing ACS Engine version: $ACS_LATEST_STABLE_VERSION"
