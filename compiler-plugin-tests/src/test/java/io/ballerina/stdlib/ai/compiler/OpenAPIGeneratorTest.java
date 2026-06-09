/*
 * Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
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
import io.ballerina.projects.DiagnosticResult;
import io.ballerina.projects.PackageCompilation;
import io.ballerina.projects.ProjectEnvironmentBuilder;
import io.ballerina.projects.directory.BuildProject;
import io.ballerina.projects.environment.Environment;
import io.ballerina.projects.environment.EnvironmentBuilder;
import io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.ballerina.tools.diagnostics.Location;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.text.MessageFormat;
import java.util.Iterator;
import java.util.regex.Pattern;

import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.UNABLE_TO_OBTAIN_VALID_SERVER_PORT_FROM_EXPRESSION;

public class OpenAPIGeneratorTest {
    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources",
            "ballerina_sources", "openapi_tests").toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime").toAbsolutePath();

    @Test
    public void testOpenAPIGenerationForListenerVariable() {
        String[] packagePaths = {
                "01_sample", "02_sample", "03_sample", "04_sample",
                "05_sample", "06_sample", "07_sample", "08_sample",
                "09_sample"
        };
        for (String packagePath : packagePaths) {
            DiagnosticResult diagnosticResult = getDiagnosticResult(packagePath);
            Assert.assertEquals(diagnosticResult.errorCount(), 0, "Expected no errors for package: " + packagePath);
            Path openApiFile = RESOURCE_DIRECTORY.resolve(packagePath + "/target/openapi/chatService_openapi.yaml");
            Assert.assertTrue(Files.exists(openApiFile), "OpenAPI file not generated for package: " + packagePath);
        }
    }

    @Test
    public void testOpenAPIGenerationForAnonymousListener() {
        String packagePath = "10_sample";
        DiagnosticResult diagnosticResult = getDiagnosticResult(packagePath);
        Assert.assertEquals(diagnosticResult.errorCount(), 0);
        Assert.assertTrue(Files
                .exists(RESOURCE_DIRECTORY.resolve(packagePath + "/target/openapi/api_v1_openapi.yaml")));
    }

    @Test
    public void testOpenAPIGenerationEmitsWarningForPortVariable() {
        String[] packagePaths = {"11_sample", "12_sample"};
        for (String packagePath : packagePaths) {
            DiagnosticResult diagnosticResult = getDiagnosticResult(packagePath);
            Assert.assertEquals(diagnosticResult.warningCount(), 1);

            Iterator<Diagnostic> diagnosticIterator = diagnosticResult.warnings().iterator();
            Diagnostic diagnostic = diagnosticIterator.next();
            String message = getWarningMessage(UNABLE_TO_OBTAIN_VALID_SERVER_PORT_FROM_EXPRESSION, "port", "9090");
            assertWarningMessage(diagnostic, message, 22, 44);

            Path openApiFile = RESOURCE_DIRECTORY.resolve(packagePath + "/target/openapi/chatService_openapi.yaml");
            Assert.assertTrue(Files.exists(openApiFile), "OpenAPI file not generated for package: " + packagePath);
        }
    }

    @Test
    public void testOpenAPIGenerationForInlineHttpListener() throws java.io.IOException {
        // 13_sample holds multiple ai:Listener services in a single package, each exercising a
        // different way of supplying an inline http:Listener (or the default listener).
        String packagePath = "13_sample";
        DiagnosticResult diagnosticResult = getDiagnosticResult(packagePath);
        Assert.assertEquals(diagnosticResult.errorCount(), 0,
                "Expected no errors for package: " + packagePath);
        Assert.assertEquals(diagnosticResult.warningCount(), 0,
                "Expected no warnings for package: " + packagePath);

        // service base path -> expected server port in the generated OpenAPI spec.
        String[][] serviceToPort = {
                {"namedService", "9091"},        // listenOn = check new http:Listener(9091)
                {"positionalService", "9092"},   // check new http:Listener(9092) (no listenOn)
                {"bracedService", "9093"},        // listenOn = check (new http:Listener(9093))
                {"reorderedService", "9094"},     // host = "127.0.0.1", port = 9094 (port not first)
                {"defaultService", "9090"},       // check http:getDefaultListener() (WI default)
                {"anonymousService", "9096"}      // anonymous ai:Listener defined on the service
        };
        for (String[] entry : serviceToPort) {
            String service = entry[0];
            String expectedPort = entry[1];
            Path openApiFile = RESOURCE_DIRECTORY.resolve(packagePath + "/target/openapi/" + service + "_openapi.yaml");
            Assert.assertTrue(Files.exists(openApiFile), "OpenAPI file not generated for service: " + service);
            String spec = Files.readString(openApiFile);
            // Match the port independently of the YAML emitter's scalar quoting style.
            Assert.assertTrue(Pattern.compile("default:\\s*\"?" + expectedPort + "\"?").matcher(spec).find(),
                    "Expected port " + expectedPort + " in the generated OpenAPI spec for " + service
                            + ", but found:\n" + spec);
        }

        // The reordered listener also specifies a named host, which must be reflected in the spec.
        String reorderedSpec = Files.readString(
                RESOURCE_DIRECTORY.resolve(packagePath + "/target/openapi/reorderedService_openapi.yaml"));
        Assert.assertTrue(reorderedSpec.contains("127.0.0.1"),
                "Expected host 127.0.0.1 in the generated OpenAPI spec, but found:\n" + reorderedSpec);
    }

    private String getWarningMessage(CompilationDiagnostic compilationDiagnostic, Object... args) {
        return MessageFormat.format(compilationDiagnostic.getDiagnostic(), args);
    }

    private void assertWarningMessage(Diagnostic diagnostic, String message, int line, int column) {
        Assert.assertEquals(diagnostic.diagnosticInfo().severity(), DiagnosticSeverity.WARNING);
        Assert.assertEquals(diagnostic.message(), message);
        assertWarningLocation(diagnostic.location(), line, column);
    }

    private void assertWarningLocation(Location location, int line, int column) {
        // Compiler counts lines and columns from zero
        Assert.assertEquals((location.lineRange().startLine().line() + 1), line);
        Assert.assertEquals((location.lineRange().startLine().offset() + 1), column);
    }

    private DiagnosticResult getDiagnosticResult(String path) {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve(path);
        BuildOptions buildOptions = BuildOptions.builder().setExportOpenAPI(true).build();
        BuildProject project = BuildProject.load(getEnvironmentBuilder(), projectDirPath, buildOptions);
        project.currentPackage().runCodeGenAndModifyPlugins();
        PackageCompilation compilation = project.currentPackage().getCompilation();
        return compilation.diagnosticResult();
    }

    private static ProjectEnvironmentBuilder getEnvironmentBuilder() {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(DISTRIBUTION_PATH).build();
        return ProjectEnvironmentBuilder.getBuilder(environment);
    }
}
