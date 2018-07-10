#!/usr/bin/env bash
set -e

REPO_URL="https://github.com/Azure/dcos-engine"
REPO_DIR="$WORKSPACE/dcos-engine"
GIT_RELEASE_BASE_URL="https://github.com/Azure/dcos-engine/releases/download"

# Get the current DCOS Engine (or set the variable to "" if the dcos-engine is not installed)
which dcos-engine > /dev/null && DCOS_ENGINE_VERSION=$(dcos-engine version | grep "Version" | awk '{print $2}') || DCOS_ENGINE_VERSION=""

rm -rf $REPO_DIR
git clone $REPO_URL $REPO_DIR
pushd $REPO_DIR

if [[ $DCOS_ENGINE_VERSION != "" ]]; then
    echo "Detected installed DCOS Engine version: $DCOS_ENGINE_VERSION. Checking if there is a newer stable DCOS Engine"
    DCOS_ENGINE_LATEST_STABLE_VERSION=$(git tag --sort=committerdate | tail -1)
    if [[ "$DCOS_ENGINE_VERSION" = "$DCOS_ENGINE_LATEST_STABLE_VERSION" ]]; then
        echo "DCOS Engine is already updated to the latest stable version: $DCOS_ENGINE_VERSION"
        popd
        rm -rf $REPO_DIR
        exit 0
    fi
    echo "New DCOS Engine version available: $DCOS_ENGINE_LATEST_STABLE_VERSION"
fi

echo "Installing DCOS Engine latest stable"

if [[ -z $DCOS_ENGINE_LATEST_STABLE_VERSION ]]; then
    DCOS_ENGINE_LATEST_STABLE_VERSION=$(git tag --sort=committerdate | tail -1)
fi
popd
rm -rf $REPO_DIR

RELEASE_URL="${GIT_RELEASE_BASE_URL}/${DCOS_ENGINE_LATEST_STABLE_VERSION}/dcos-engine-${DCOS_ENGINE_LATEST_STABLE_VERSION}-linux-amd64.tar.gz"
OUT_FILE="dcos-engine-${DCOS_ENGINE_LATEST_STABLE_VERSION}-linux-amd64.tar.gz"

cd $WORKSPACE
EXIT_CODE=0
OUTPUT=$(wget $RELEASE_URL -O $OUT_FILE 2>&1) || EXIT_CODE=1
if [[ $EXIT_CODE -ne 0 ]]; then
    if echo $OUTPUT | grep -q "ERROR 404"; then
        echo "There isn't a git download URL for the new version: $DCOS_ENGINE_LATEST_STABLE_VERSION. Will still use DCOS Engine version: $DCOS_ENGINE_VERSION"
        exit 0
    else
        echo $OUTPUT
        exit 1
    fi
fi

tar xzf $OUT_FILE
EXTRACT_DIR="dcos-engine-${DCOS_ENGINE_LATEST_STABLE_VERSION}-linux-amd64"
mkdir -p $WORKSPACE/bin
export PATH="$WORKSPACE/bin:$PATH"
mv $EXTRACT_DIR/dcos-engine $WORKSPACE/bin/dcos-engine
chmod +x $WORKSPACE/bin/dcos-engine
rm -rf $EXTRACT_DIR $OUT_FILE

echo "Finished installing DCOS Engine version: $DCOS_ENGINE_LATEST_STABLE_VERSION"
