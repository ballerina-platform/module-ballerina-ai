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

import io.ballerina.projects.BuildOptions;
import io.ballerina.projects.JBallerinaBackend;
import io.ballerina.projects.JvmTarget;
import io.ballerina.projects.PackageCompilation;
import io.ballerina.projects.ProjectEnvironmentBuilder;
import io.ballerina.projects.directory.BuildProject;
import io.ballerina.projects.environment.Environment;
import io.ballerina.projects.environment.EnvironmentBuilder;
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
import java.util.stream.Stream;

/**
 * End-to-end tests for the {@code --export-endpoints} build option: each fixture is built the way {@code bal build}
 * builds it and the resulting {@code target/artifact/endpoints.yaml} and chat service OpenAPI specifications are
 * asserted. The build runs in-process, so the compiler plugin is exercised within the test JVM.
 */
public class EndpointExportTest {
    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources",
            "ballerina_sources", "endpoint_export_tests").toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime").toAbsolutePath();
    private static final String ARTIFACT_DIR = "artifact";
    private static final String ENDPOINTS_FILE = "endpoints.yaml";

    static {
        // Code generation resolves the Ballerina runtime from the Ballerina home, which `bal` sets for a CLI build
        System.setProperty("ballerina.home", DISTRIBUTION_PATH.toString());
    }

    @Test
    public void testListenerVariants() throws IOException {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("listener_variants");
        try {
            Assert.assertTrue(build(projectDirPath, true), "Expected the package to build");
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
    public void testBuildWithoutExportFlagProducesNoArtifact() throws IOException {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("listener_variants");
        try {
            Assert.assertTrue(build(projectDirPath, false), "Expected the package to build");
            Assert.assertTrue(Files.notExists(artifactDir(projectDirPath)),
                    "No artifact should be generated without --export-endpoints");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testCompilationErrorProducesNoArtifact() throws IOException {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("compilation_error");
        try {
            Assert.assertFalse(build(projectDirPath, true), "The fixture is expected to have compilation errors");
            Assert.assertTrue(Files.notExists(artifactDir(projectDirPath)),
                    "No artifact should be generated for a package with compilation errors");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testServiceInTestSourceIsSkipped() throws IOException {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("service_in_test_source");
        try {
            Assert.assertTrue(build(projectDirPath, true), "Expected the package to build");
            String endpoints = Files.readString(artifactDir(projectDirPath).resolve(ENDPOINTS_FILE));
            Assert.assertEquals(getEntries(endpoints).size(), 1, endpoints);
            assertAiEndpoint(projectDirPath, endpoints, "/main", 9095, "main_main_openapi.yaml");
            Assert.assertNull(findEntry(endpoints, "/test"), "A service in test sources must not be exported");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testServicesOnRootBasePath() throws IOException {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("root_base_paths");
        try {
            Assert.assertTrue(build(projectDirPath, true), "Expected the package to build");
            String endpoints = Files.readString(artifactDir(projectDirPath).resolve(ENDPOINTS_FILE));
            List<String> entries = getEntries(endpoints);
            Assert.assertEquals(entries.size(), 2, endpoints);

            // The first root service is named after the file alone; the next one in the same file gets a
            // symbol-based suffix so the specifications do not overwrite each other
            List<String> schemaFileNames = entries.stream()
                    .map(entry -> entry.replaceAll("(?s).*schemaPath: \"([^\"]+)\".*", "$1"))
                    .sorted()
                    .toList();
            Assert.assertTrue(schemaFileNames.contains("main_openapi.yaml"), endpoints);
            Assert.assertTrue(schemaFileNames.stream().anyMatch(name -> name.matches("main_-?\\d+_openapi\\.yaml")),
                    endpoints);
            for (String schemaFileName : schemaFileNames) {
                Assert.assertTrue(Files.exists(artifactDir(projectDirPath).resolve(schemaFileName)),
                        "OpenAPI specification not generated: " + schemaFileName);
            }
            Assert.assertTrue(endpoints.contains("port: 9095"), endpoints);
            Assert.assertTrue(endpoints.contains("port: 9096"), endpoints);
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testPackageWithoutAiServicesProducesNoArtifact() throws IOException {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("no_ai_services");
        try {
            Assert.assertTrue(build(projectDirPath, true), "Expected the package to build");
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

    /**
     * Builds the package as {@code bal build} does: runs the code generators and modifiers, compiles the package and,
     * if it compiles without errors, emits the executable, which also writes the exported endpoints.
     *
     * @param projectDirPath  the package directory
     * @param exportEndpoints whether the {@code --export-endpoints} build option is enabled
     * @return {@code true} if the executable was emitted
     */
    private static boolean build(Path projectDirPath, boolean exportEndpoints) throws IOException {
        deleteDirectories(projectDirPath);
        BuildOptions buildOptions = BuildOptions.builder().setExportEndpoints(exportEndpoints).build();
        BuildProject project = BuildProject.load(getEnvironmentBuilder(), projectDirPath, buildOptions);
        project.currentPackage().runCodeGenAndModifyPlugins();
        PackageCompilation compilation = project.currentPackage().getCompilation();
        if (compilation.diagnosticResult().hasErrors()) {
            return false;
        }
        Path binDir = Files.createDirectories(project.targetDir().resolve("bin"));
        Path executable = binDir.resolve(project.currentPackage().packageName().value() + ".jar");
        JBallerinaBackend backend = JBallerinaBackend.from(compilation, JvmTarget.JAVA_25);
        return backend.emit(JBallerinaBackend.OutputType.EXEC, executable).successful();
    }

    private static ProjectEnvironmentBuilder getEnvironmentBuilder() {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(DISTRIBUTION_PATH).build();
        return ProjectEnvironmentBuilder.getBuilder(environment);
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
