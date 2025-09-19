#!/bin/bash
set -x
GRAALPY_VERSION="graal-24.2.2"
TAR_FILE="graalpy-24.2.2-linux-amd64.tar.gz"
VENV_DIR="linux"
RESOURCE_DIR=../native/src/main/resources
wget https://github.com/oracle/graalpython/releases/download/graal-24.2.2/graalpy-24.2.2-linux-amd64.tar.gz

tar -xzf $TAR_FILE

./graalpy-24.2.2-linux-amd64/bin/graalpy -m venv $VENV_DIR

source ./linux/bin/activate

echo "Using CC=$CC"
echo "Using CXX=$CXX"

pip3 install -r requirements.txt

mkdir -p $RESOURCE_DIR/venvs/linux
# Copy venv directory and resolve symlinks to avoid broken absolute paths
cp -rL $VENV_DIR $RESOURCE_DIR/venvs/linux/venv
mkdir -p $RESOURCE_DIR/venvs/linux/std-lib
cp -r graalpy-24.2.2-linux-amd64/lib/python3.11 $RESOURCE_DIR/venvs/linux/std-lib/python3.11
