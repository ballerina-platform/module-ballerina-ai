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

package io.ballerina.stdlib.ai.unified;

import java.io.File;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.Optional;

/**
 * Platform-agnostic observability manager that dynamically loads
 * the appropriate platform-specific observability implementation.
 */
public class PlatformObservabilityManager {

    private static final String OBSERVABILITY_CLASS = "io.ballerina.stdlib.ai.observability.Observability";
    private static final String TRACER_FIELD = "TRACER";

    private static volatile Class<?> observabilityClass;
    private static volatile ClassLoader platformClassLoader;
    private static volatile boolean initialized = false;
    private static volatile Exception initializationError;

    static {
        initializePlatformSpecificObservability();
    }

    private static void initializePlatformSpecificObservability() {
        try {
            String platform = detectPlatform();
            System.out.println("Detected platform: " + platform);

            Optional<URLClassLoader> platformClassLoaderOpt = loadPlatformSpecificJar(platform);
            if (platformClassLoaderOpt.isPresent()) {
                platformClassLoader = platformClassLoaderOpt.get();
                observabilityClass = platformClassLoader.loadClass(OBSERVABILITY_CLASS);
                // No need to instantiate - all methods are static
                initialized = true;
                System.out.println("Successfully loaded platform-specific observability for: " + platform);
            } else {
                throw new RuntimeException("No platform-specific JAR found for platform: " + platform);
            }
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private static String detectPlatform() {
        String osName = System.getProperty("os.name").toLowerCase();
        String osArch = System.getProperty("os.arch").toLowerCase();

        if (osName.contains("mac") || osName.contains("darwin")) {
            return "darwin-" + normalizeArch(osArch);
        } else if (osName.contains("linux")) {
            return "linux-" + normalizeArch(osArch);
        } else if (osName.contains("windows")) {
            return "windows-" + normalizeArch(osArch);
        }

        throw new UnsupportedOperationException("Unsupported platform: " + osName + " " + osArch);
    }

    private static String normalizeArch(String arch) {
        if (arch.contains("aarch64") || arch.contains("arm64")) {
            return "aarch64";
        } else if (arch.contains("x86_64") || arch.contains("amd64")) {
            return "amd64";
        }
        return arch;
    }

    private static Optional<URLClassLoader> loadPlatformSpecificJar(String platform) {
        // Look for platform-specific JAR in project root
        String jarPattern = "observability-native-.*-" + platform + "\\.jar";
        System.out.println("Looking for JAR with pattern: " + jarPattern);

        File projectRoot = new File(System.getProperty("user.dir"));
        // If we're in a submodule, look in the parent directory for JARs
        if (!projectRoot.getName().equals("module-ballerina-ai") && projectRoot.getParent() != null) {
            projectRoot = new File(projectRoot.getParent());
        }
        System.out.println("Searching in directory: " + projectRoot.getAbsolutePath());

        File[] allJars = projectRoot.listFiles((dir, name) -> name.endsWith(".jar"));
        if (allJars != null) {
            System.out.println("Available JAR files:");
            for (File jar : allJars) {
                System.out.println("  " + jar.getName());
            }
        }

        File[] jarFiles = projectRoot.listFiles((dir, name) -> name.matches(jarPattern));

        if (jarFiles != null && jarFiles.length > 0) {
            try {
                File jarFile = jarFiles[0];
                System.out.println("Loading platform JAR: " + jarFile.getAbsolutePath());
                URL jarUrl = jarFile.toURI().toURL();
                return Optional.of(new URLClassLoader(new URL[]{jarUrl},
                    Thread.currentThread().getContextClassLoader()));
            } catch (Exception e) {
                System.err.println("Failed to load JAR: " + e.getMessage());
            }
        }

        return Optional.empty();
    }

    /**
     * Initialize tracing with the specified Phoenix endpoint and project name.
     * This method delegates to the platform-specific implementation.
     *
     * @param phoenixEndpoint The Phoenix collector endpoint
     * @param projectName The project name for tracing
     * @throws RuntimeException if platform-specific implementation is not available
     */
    public static void initTracing(String phoenixEndpoint, String projectName) {
        if (!initialized) {
            if (initializationError != null) {
                throw new RuntimeException("Platform-specific observability not available", initializationError);
            }
            throw new RuntimeException("Platform-specific observability not initialized");
        }

        try {
            var method = observabilityClass.getMethod("initTracing", String.class, String.class);
            method.invoke(null, phoenixEndpoint, projectName);
        } catch (Exception e) {
            throw new RuntimeException("Failed to initialize tracing", e);
        }
    }

    /**
     * Get the tracer constant from the platform-specific implementation.
     *
     * @return The tracer constant string
     * @throws RuntimeException if platform-specific implementation is not available
     */
    public static String getTracer() {
        if (!initialized) {
            if (initializationError != null) {
                throw new RuntimeException("Platform-specific observability not available", initializationError);
            }
            throw new RuntimeException("Platform-specific observability not initialized");
        }

        try {
            var field = observabilityClass.getField(TRACER_FIELD);
            return (String) field.get(null);
        } catch (Exception e) {
            throw new RuntimeException("Failed to get tracer", e);
        }
    }

    /**
     * Check if the platform-specific observability is available and initialized.
     *
     * @return true if available, false otherwise
     */
    public static boolean isAvailable() {
        return initialized;
    }

    /**
     * Get the initialization error if any occurred.
     *
     * @return Optional containing the error, or empty if no error
     */
    public static Optional<Exception> getInitializationError() {
        return Optional.ofNullable(initializationError);
    }

    /**
     * Get information about the detected platform.
     *
     * @return Platform information string
     */
    public static String getPlatformInfo() {
        try {
            return detectPlatform();
        } catch (Exception e) {
            return "Unknown platform: " + e.getMessage();
        }
    }

    /**
     * Get the platform-specific class loader.
     *
     * @return The platform class loader
     * @throws RuntimeException if platform-specific implementation is not available
     */
    public static ClassLoader getPlatformClassLoader() {
        if (!initialized) {
            if (initializationError != null) {
                throw new RuntimeException("Platform-specific observability not available", initializationError);
            }
            throw new RuntimeException("Platform-specific observability not initialized");
        }
        return platformClassLoader;
    }
}
