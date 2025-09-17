#!/bin/bash

#
#  Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
#
#  WSO2 LLC. licenses this file to you under the Apache License,
#  Version 2.0 (the "License"); you may not use this file except
#  in compliance with the License.
#  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing,
#  software distributed under the License is distributed on an
#  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#  KIND, either express or implied.  See the License for the
#  specific language governing permissions and limitations
#  under the License.
#

export MACOSX_DEPLOYMENT_TARGET=11.0
# Add our wrapper script to the front of PATH so it gets used instead of system gcc
export PATH="$(pwd):$PATH"

# Set CC to use our wrapper
export CC="$(pwd)/gcc-wrapper"

# Keep CXX as g++ for explicit C++ compilation
export CXX=g++

echo "Using CC=$CC"
echo "Using CXX=$CXX"

# Install GraalPy if not available or use provided path
if [ -z "$GRAALPY" ]; then
    # Check if graalpy is available in PATH
    if command -v graalpy &> /dev/null; then
        GRAALPY="graalpy"
    else
        echo "Error: GRAALPY environment variable not set and graalpy not found in PATH"
        echo "Please set GRAALPY to the path of your GraalPy executable"
        exit 1
    fi
fi

echo "Using GRAALPY=$GRAALPY"

# Run the Gradle command using standalone build, skip tests (no Docker available)
./gradlew clean build -x test -Dgraalpy.vfs.venvLauncher="$GRAALPY"
