#!/bin/bash

export MACOSX_DEPLOYMENT_TARGET=11.0
# Add our wrapper script to the front of PATH so it gets used instead of system gcc
export PATH="$(pwd):$PATH"

# Set CC to use our wrapper
export CC="$(pwd)/gcc-wrapper"

# Keep CXX as g++ for explicit C++ compilation
export CXX=g++

echo "Using CC=$CC"
echo "Using CXX=$CXX"

# Run the Gradle command
../gradlew build -Dgraalpy.vfs.venvLauncher="$GRAALPY"

