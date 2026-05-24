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

import io.ballerina.projects.DiagnosticResult;
import io.ballerina.projects.Document;
import io.ballerina.projects.DocumentId;
import io.ballerina.projects.Module;
import io.ballerina.projects.ProjectEnvironmentBuilder;
import io.ballerina.projects.directory.BuildProject;
import io.ballerina.projects.environment.Environment;
import io.ballerina.projects.environment.EnvironmentBuilder;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Tests that the compiler plugin adds `@ai:JsonSchema` annotations for record types used as the inferred return type of
 * `ai:Agent.run` calls.
 */
public class JsonSchemaModificationTest {

    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources",
            "ballerina_sources", "json_schema_tests").toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime").toAbsolutePath();

    @Test
    public void testSchemaAnnotationAddedForAgentRunRecordReturn() {
        BuildProject project = BuildProject.load(getEnvironmentBuilder(),
                RESOURCE_DIRECTORY.resolve("01_agent_run_record_return"));
        DiagnosticResult diagnosticResult = project.currentPackage().runCodeGenAndModifyPlugins();
        Assert.assertEquals(diagnosticResult.errorCount(), 0,
                "Expected no compilation errors in the agent run record return source");

        String modifiedSource = getModifiedSource(project);
        Assert.assertTrue(modifiedSource.contains("@ai:JsonSchema"),
                "Expected an @ai:JsonSchema annotation to be generated for the agent run return type");
        Assert.assertTrue(modifiedSource.contains("\"name\"") && modifiedSource.contains("\"age\""),
                "Expected the generated schema to describe the record's fields");
    }

    private static String getModifiedSource(BuildProject project) {
        StringBuilder builder = new StringBuilder();
        Module module = project.currentPackage().getDefaultModule();
        for (DocumentId documentId : module.documentIds()) {
            Document document = module.document(documentId);
            builder.append(document.syntaxTree().toSourceCode());
        }
        return builder.toString();
    }

    private static ProjectEnvironmentBuilder getEnvironmentBuilder() {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(DISTRIBUTION_PATH).build();
        return ProjectEnvironmentBuilder.getBuilder(environment);
    }
}
