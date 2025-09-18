#!/bin/bash
set -x
GRAALPY_VERSION="graal-24.2.2"
GRAALPY_DIR="graalpy-$GRAALPY_VERSION-macos-aarch64"
TAR_FILE="graalpy-24.2.2-macos-aarch64.tar.gz"
VENV_DIR="darwin"
RESOURCE_DIR=../native/src/main/resources
wget https://github.com/oracle/graalpython/releases/download/graal-24.2.2/$TAR_FILE

tar -xzf $TAR_FILE

./graalpy-24.2.2-macos-aarch64/bin/graalpy -m venv $VENV_DIR

source ./darwin/bin/activate

export MACOSX_DEPLOYMENT_TARGET=11.0
# Add our wrapper script to the front of PATH so it gets used instead of system gcc
export PATH="$(pwd):$PATH"

# Set CC to use our wrapper
export CC="$(pwd)/gcc-wrapper"

# Keep CXX as g++ for explicit C++ compilation
export CXX=g++

echo "Using CC=$CC"
echo "Using CXX=$CXX"

pip3 install -r requirements.txt

mkdir -p $RESOURCE_DIR/venvs/darwin
cp -r $VENV_DIR $RESOURCE_DIR/venvs/darwin/venv
mkdir -p $RESOURCE_DIR/venvs/darwin/std-lib
cp -r graalpy-24.2.2-macos-aarch64/lib/python3.11 $RESOURCE_DIR/venvs/darwin/std-lib/python3.11
