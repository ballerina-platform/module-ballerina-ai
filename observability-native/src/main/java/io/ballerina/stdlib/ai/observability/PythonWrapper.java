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

import org.graalvm.polyglot.Context;

import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

public class PythonWrapper {

    private static final PrintStream out = System.out;

    private enum OperatingSystem {
        LINUX("linux"),
        DARWIN("darwin");

        private final String name;

        OperatingSystem(String name) {
            this.name = name;
        }

        public String getName() {
            return name;
        }

        public String getSitePackagesPath() {
            return this.name + "-venv/venv/lib/python3.11/site-packages";
        }

        public String getStdLibPath() {
            return this.name + "-venv/std-lib/python3.11";
        }

        public static OperatingSystem detect() {
            String osName = System.getProperty("os.name").toLowerCase(Locale.ENGLISH);
            if (osName.contains("linux")) {
                return LINUX;
            } else if (osName.contains("mac") || osName.contains("darwin")) {
                return DARWIN;
            } else {
                throw new RuntimeException("Unsupported operating system: " + osName);
            }
        }
    }

    private static class ContextHolder {

        private static final Context CONTEXT = createContext();

        private static final String VENV_METADATA_FILE = "venv-metadata.json";

        private static String version() {
            try (InputStream inputStream = PythonWrapper.class.getClassLoader()
                    .getResourceAsStream(VENV_METADATA_FILE)) {
                if (inputStream == null) {
                    throw new IOException("Venv metadata file not found in classpath: " + VENV_METADATA_FILE);
                }
                String jsonContent = new String(inputStream.readAllBytes(), StandardCharsets.UTF_8);

                // Parse JSON to extract version value
                Pattern pattern = Pattern.compile("\"version\"\\s*:\\s*\"([^\"]+)\"");
                Matcher matcher = pattern.matcher(jsonContent);
                if (matcher.find()) {
                    return matcher.group(1);
                } else {
                    throw new RuntimeException("Version not found in venv metadata file");
                }
            } catch (IOException e) {
                throw new RuntimeException("Failed to read venv metadata file", e);
            }
        }

        private static Path getVenvPath() {
            String version = version();
            String homeDir = System.getProperty("user.home");
            return Paths.get(homeDir, ".ballerina", "venv", "ai", version);
        }

        private static Context createContext() {
            try {
                // Detect operating system
                OperatingSystem os = OperatingSystem.detect();

                // Create temp directory and copy venv resources
                Path tempDir = getVenvPath();
                if (!Files.exists(tempDir)) {
                    Files.createDirectories(tempDir);
                    copyVenvResourceToDirectory(tempDir.toString(), os);
                }

                String sitePackagesPath = tempDir.resolve(os.getSitePackagesPath()).toString();
                String stdLibPath = tempDir.resolve(os.getStdLibPath()).toString();

                return Context.newBuilder("python")
                        .option("python.PythonPath", sitePackagesPath + ":" + stdLibPath)
                        .option("python.StdLibHome", stdLibPath)
                        .option("python.ForceImportSite", "true")
                        .allowAllAccess(true)
                        .build();
            } catch (Exception e) {
                throw new RuntimeException("Failed to initialize Python context due to" + e.getMessage(), e);
            }
        }

        private static void copyVenvResourceToDirectory(String target, OperatingSystem os) throws IOException {
            String zipFileName = os.getName() + "-venv.zip";

            // Try to get the resource from the classpath
            try (InputStream inputStream = PythonWrapper.class.getClassLoader().getResourceAsStream(zipFileName)) {
                if (inputStream == null) {
                    throw new IOException("Zip file not found in classpath: " + zipFileName);
                }

                try (ZipInputStream zipInputStream = new ZipInputStream(inputStream)) {
                    ZipEntry entry;
                    while ((entry = zipInputStream.getNextEntry()) != null) {
                        String entryName = entry.getName();
                        Path targetPath = Paths.get(target, entryName);

                        // Skip if it's a directory entry
                        if (entry.isDirectory()) {
                            Files.createDirectories(targetPath);
                            continue;
                        }

                        // Create parent directories if they don't exist
                        Path parent = targetPath.getParent();
                        if (parent != null) {
                            Files.createDirectories(parent);
                        }

                        // Extract the file
                        Files.copy(zipInputStream, targetPath, StandardCopyOption.REPLACE_EXISTING);
                        zipInputStream.closeEntry();
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
