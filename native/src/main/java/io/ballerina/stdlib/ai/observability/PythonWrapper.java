/*
 *  Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
 *
 *  WSO2 LLC. licenses this file to you under the Apache License,
 *  Version 2.0 (the "License"); you may not use this file except
 *  in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing,
 *  software distributed under the License is distributed on an
 *  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 *  KIND, either express or implied.  See the License for the
 *  specific language governing permissions and limitations
 *  under the License.
 */

package io.ballerina.stdlib.ai.observability;

import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;

import io.github.classgraph.ClassGraph;
import io.github.classgraph.Resource;
import io.github.classgraph.ScanResult;
import org.graalvm.polyglot.Context;

public class PythonWrapper {

    private static final PrintStream out = System.out;

    private static class ContextHolder {

        private static final Context CONTEXT = createContext();

        private static Context createContext() {
            try {
                // Create temp directory and copy venv resources
                Path tempDir = Files.createTempDirectory("ballerina-ai-python");
                copyVenvResourceToDirectory(tempDir.toString());

                String sitePackagesPath = tempDir.resolve("venvs/darwin/lib/python3.11/site-packages").toString();
                String stdLibPath = tempDir.resolve("venvs/darwin-std-lib/python3.11").toString();

                return Context.newBuilder("python")
                        .option("python.PythonPath", sitePackagesPath + ":" + stdLibPath)
                        .option("python.StdLibHome", stdLibPath)
                        .option("python.ForceImportSite", "true")
                        .allowAllAccess(true)
                        .build();
            } catch (Exception e) {
                throw new RuntimeException("Failed to initialize Python context", e);
            }
        }

        private static void copyVenvResourceToDirectory(String target) throws IOException {
            try (ScanResult scanResult = new ClassGraph()
                    .acceptPaths("venvs")
                    .enableAllInfo()
                    .scan()) {
                for (Resource resource : scanResult.getAllResources()) {
                    String resourcePath = resource.getPath();
                    Path targetPath = Paths.get(target, resourcePath);

                    // Create parent directories if they don't exist
                    Path parent = targetPath.getParent();
                    if (parent != null) {
                        Files.createDirectories(parent);
                    }

                    // Copy the resource to the target path
                    try (InputStream inputStream = resource.open()) {
                        Files.copy(inputStream, targetPath, StandardCopyOption.REPLACE_EXISTING);
                    }
                }
            }
        }
    }

    private static Context getContext() {
        return ContextHolder.CONTEXT;
    }

    public static synchronized void execVoid(String code) {
        String debugPy = System.getenv("DEBUG_PY");
        boolean isDebug = debugPy != null && !debugPy.isEmpty();
        try {
            getContext().eval("python", code);
            if (isDebug) {
                out.println("Executed Python code:\n" + code);
            }
        } catch (Exception e) {
            if (isDebug) {
                throw new RuntimeException("error executing: " + code, e);
            } else {
                throw new RuntimeException("unexpected error", e);
            }
        }
    }
}
