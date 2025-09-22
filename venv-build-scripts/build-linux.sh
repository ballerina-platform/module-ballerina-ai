#!/bin/bash
set -x
GRAALPY_VERSION="24.2.2"

GRAALPY_DIR="graalpy-$GRAALPY_VERSION-linux-amd64"
TAR_FILE="graalpy-$GRAALPY_VERSION-linux-amd64.tar.gz"
VENV_DIR="linux"
ZIP_NAME="linux-venv"
RESOURCE_DIR=../observability-native/src/main/resources
wget https://github.com/oracle/graalpython/releases/download/graal-$GRAALPY_VERSION/$TAR_FILE

tar -xzf $TAR_FILE

./$GRAALPY_DIR/bin/graalpy -m venv $VENV_DIR

source ./$VENV_DIR/bin/activate

echo "Using CC=$CC"
echo "Using CXX=$CXX"

pip3 install -r requirements.txt

# Extract version from gradle.properties and write to venv-metadata.json
VERSION=$(grep "^version=" ../gradle.properties | cut -d'=' -f2)
echo "{\"version\": \"$VERSION\"}" > $ZIP_NAME/venv-metadata.json

mkdir -p $ZIP_NAME
cp -r $VENV_DIR $ZIP_NAME/venv
rm -rf $ZIP_NAME/venv/bin
mkdir -p $ZIP_NAME/std-lib
cp -r $GRAALPY_DIR/lib/python3.11 $ZIP_NAME/std-lib/python3.11
zip -rq $ZIP_NAME.zip $ZIP_NAME
mv $ZIP_NAME.zip $RESOURCE_DIR/
rm -rf $ZIP_NAME
rm -rf $VENV_DIR
rm -rf $TAR_FILE $GRAALPY_DIR
