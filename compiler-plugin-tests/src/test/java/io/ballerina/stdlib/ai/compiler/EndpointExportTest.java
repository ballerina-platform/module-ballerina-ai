/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.stdlib.ai.compiler;

import org.testng.Assert;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

/**
 * End-to-end tests for the {@code --export-endpoints} build option: each fixture is built with {@code bal build} and
 * the resulting {@code target/artifact/endpoints.yaml} and chat service OpenAPI specifications are asserted.
 */
public class EndpointExportTest {
    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources",
            "ballerina_sources", "endpoint_export_tests").toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime").toAbsolutePath();
    private static final String ARTIFACT_DIR = "artifact";
    private static final String ENDPOINTS_FILE = "endpoints.yaml";

    @Test
    public void testListenerVariants() throws IOException, InterruptedException {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("listener_variants");
        try {
            Assert.assertEquals(executeBallerinaCommand(projectDirPath, true), 0);
            String endpoints = Files.readString(artifactDir(projectDirPath).resolve(ENDPOINTS_FILE));

            // The HTTP service in the same package is exported by the HTTP module alongside the AI agent services
            Assert.assertEquals(getEntries(endpoints).size(), 4, endpoints);
            assertAiEndpoint(projectDirPath, endpoints, "/chatService", 9095, "main_chatService_openapi.yaml");
            assertAiEndpoint(projectDirPath, endpoints, "/api/v1/agent", 9097, "main_api_v1_agent_openapi.yaml");
            assertAiEndpoint(projectDirPath, endpoints, "/inline", 9096, "main_inline_openapi.yaml");
            Assert.assertNotNull(findEntry(endpoints, "/hello"), endpoints);
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testBuildWithoutExportFlagProducesNoArtifact() throws IOException, InterruptedException {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("listener_variants");
        try {
            Assert.assertEquals(executeBallerinaCommand(projectDirPath, false), 0);
            Assert.assertTrue(Files.notExists(artifactDir(projectDirPath)),
                    "No artifact should be generated without --export-endpoints");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testCompilationErrorProducesNoArtifact() throws IOException, InterruptedException {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("compilation_error");
        try {
            Assert.assertNotEquals(executeBallerinaCommand(projectDirPath, true), 0,
                    "The fixture is expected to have compilation errors");
            Assert.assertTrue(Files.notExists(artifactDir(projectDirPath)),
                    "No artifact should be generated for a package with compilation errors");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testServiceInTestSourceIsSkipped() throws IOException, InterruptedException {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("service_in_test_source");
        try {
            Assert.assertEquals(executeBallerinaCommand(projectDirPath, true), 0);
            String endpoints = Files.readString(artifactDir(projectDirPath).resolve(ENDPOINTS_FILE));
            Assert.assertEquals(getEntries(endpoints).size(), 1, endpoints);
            assertAiEndpoint(projectDirPath, endpoints, "/main", 9095, "main_main_openapi.yaml");
            Assert.assertNull(findEntry(endpoints, "/test"), "A service in test sources must not be exported");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testPackageWithoutAiServicesProducesNoArtifact() throws IOException, InterruptedException {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("no_ai_services");
        try {
            Assert.assertEquals(executeBallerinaCommand(projectDirPath, true), 0);
            Assert.assertTrue(Files.notExists(artifactDir(projectDirPath)),
                    "No artifact should be generated for a package without services");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    private static void assertAiEndpoint(Path projectDirPath, String endpoints, String basePath, int port,
                                         String schemaFileName) throws IOException {
        String entry = findEntry(endpoints, basePath);
        Assert.assertNotNull(entry, "No endpoint exported for " + basePath + " in:\n" + endpoints);
        Assert.assertTrue(entry.contains("port: " + port), entry);
        Assert.assertTrue(entry.contains("type: \"REST\""), entry);
        Assert.assertTrue(entry.contains("schemaPath: \"" + schemaFileName + "\""), entry);

        Path schemaFile = artifactDir(projectDirPath).resolve(schemaFileName);
        Assert.assertTrue(Files.exists(schemaFile), "OpenAPI specification not generated for " + basePath);
        String spec = Files.readString(schemaFile);
        Assert.assertTrue(spec.contains("{server}:{port}" + basePath), spec);
        Assert.assertTrue(spec.contains("/chat:"), spec);
    }

    private static List<String> getEntries(String endpoints) {
        List<String> entries = new ArrayList<>(Arrays.asList(endpoints.split("- name:")));
        // Drop the content preceding the first entry
        entries.removeFirst();
        return entries;
    }

    private static String findEntry(String endpoints, String basePath) {
        return getEntries(endpoints).stream()
                .filter(entry -> entry.contains("basePath: \"" + basePath + "\""))
                .findFirst()
                .orElse(null);
    }

    private static Path artifactDir(Path projectDirPath) {
        return projectDirPath.resolve("target").resolve(ARTIFACT_DIR);
    }

    private static int executeBallerinaCommand(Path projectDirPath, boolean exportEndpoints)
            throws IOException, InterruptedException {
        deleteDirectories(projectDirPath);
        List<String> buildArgs = new ArrayList<>();
        String balFile = System.getProperty("os.name").startsWith("Windows") ? "bal.bat" : "bal";
        buildArgs.add(DISTRIBUTION_PATH.resolve("bin").resolve(balFile).toString());
        buildArgs.add("build");
        if (exportEndpoints) {
            buildArgs.add("--export-endpoints");
        }

        ProcessBuilder pb = new ProcessBuilder(buildArgs)
                .redirectErrorStream(true)
                .redirectOutput(ProcessBuilder.Redirect.INHERIT);
        pb.directory(projectDirPath.toFile());
        Process process = pb.start();
        if (!process.waitFor(2, TimeUnit.MINUTES)) {
            process.destroyForcibly().waitFor();
            Assert.fail("bal build timed out after 2 minutes");
        }
        return process.exitValue();
    }

    private static void deleteDirectories(Path projectDirPath) throws IOException {
        Path targetDir = projectDirPath.resolve("target");
        if (Files.exists(targetDir)) {
            try (Stream<Path> paths = Files.walk(targetDir)) {
                for (Path path : paths.sorted(Comparator.reverseOrder()).toList()) {
                    Files.delete(path);
                }
            }
        }
        Files.deleteIfExists(projectDirPath.resolve("Dependencies.toml"));
    }
}
