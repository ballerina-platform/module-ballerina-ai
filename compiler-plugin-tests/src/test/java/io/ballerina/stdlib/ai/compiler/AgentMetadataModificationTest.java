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
 * Tests that the compiler plugin attaches an `@ai:AgentMetadata` annotation, listing the statically identifiable tool
 * names, to custom agent definitions (classes implementing `ai:AgentType`).
 * <p>
 * Note: there is no test for an `ai:InferredReturnAgentType` subtype because its `run` method is dependently-typed and
 * therefore cannot be implemented in user code (it would have to be `external`).
 */
public class AgentMetadataModificationTest {

    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources",
            "ballerina_sources", "agent_metadata_tests").toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime").toAbsolutePath();

    @Test
    public void testAgentMetadataAnnotationForCustomAgent() {
        String modifiedSource = getModifiedSourceForProject("01_custom_agent_basic");
        Assert.assertTrue(modifiedSource.contains(
                        "@ai:AgentMetadata {tools: [\"createSchedule\", \"coordinateSpeakers\", \"searchTool\"]}"),
                "Expected an @ai:AgentMetadata annotation listing the object method tool, the module-level "
                        + "function tool, and the inline ToolConfig tool");
    }

    @Test
    public void testAgentMetadataAnnotationWithToolKit() {
        String modifiedSource = getModifiedSourceForProject("02_custom_agent_with_toolkit");
        Assert.assertTrue(modifiedSource.contains("@ai:AgentMetadata {tools: [\"getDiscounts\"]}"),
                "Expected the annotation to list only the statically identifiable function tool, "
                        + "skipping the toolkit");
        Assert.assertTrue(modifiedSource.contains("@ai:AgentMetadata {tools: []}"),
                "Expected an annotation with an empty tools list for the toolkit-only agent");
    }

    @Test
    public void testNoAgentMetadataAnnotationForNonAgentClass() {
        String modifiedSource = getModifiedSourceForProject("03_non_agent_class");
        Assert.assertFalse(modifiedSource.contains("@ai:AgentMetadata"),
                "No @ai:AgentMetadata annotation should be attached to a class that does not implement "
                        + "ai:AgentType");
    }

    @Test
    public void testUserWrittenAgentMetadataAnnotationIsPreserved() {
        String modifiedSource = getModifiedSourceForProject("04_user_written_annotation");
        Assert.assertTrue(modifiedSource.contains("@ai:AgentMetadata {tools: [\"manuallyListedTool\"]}"),
                "Expected the user-written @ai:AgentMetadata annotation to be preserved");
        Assert.assertFalse(modifiedSource.contains("@ai:AgentMetadata {tools: [\"reportWeather\"]}"),
                "The generated tool list must not overwrite the user-written annotation");
    }

    @Test
    public void testAgentMetadataAnnotationWithAliasedImport() {
        String modifiedSource = getModifiedSourceForProject("05_aliased_import");
        Assert.assertTrue(modifiedSource.contains("@intelligence:AgentMetadata {tools: [\"answerMath\"]}"),
                "Expected the generated annotation to use the aliased ballerina/ai import prefix");
    }

    @Test
    public void testAgentMetadataAnnotationWithExplicitNewAndQualifiedTool() {
        String modifiedSource = getModifiedSourceForProject("06_explicit_new_and_qualified");
        Assert.assertTrue(modifiedSource.contains(
                        "@ai:AgentMetadata {tools: [\"localTool\", \"remoteLookup\", \"inlineNamed\"]}"),
                "Expected explicit `new ai:Agent(...)`, qualified tool references, and inline ToolConfigs "
                        + "to be handled, skipping the variable and the non-literal name");
    }

    @Test
    public void testAgentMetadataAnnotationForEdgeCases() {
        String modifiedSource = getModifiedSourceForProject("07_edge_cases");
        // `tools = <variable>` is not a list literal, so no tools are read; the directly-implemented agent
        // has no `init`. Both are still discoverable agents, so both get an empty tools list.
        int emptyToolsCount = countOccurrences(modifiedSource, "@ai:AgentMetadata {tools: []}");
        Assert.assertEquals(emptyToolsCount, 2,
                "Expected an empty tools annotation for both the dynamic-tools agent and the agent with no "
                        + "init method");
        // The agent that already had a `@Labelled` annotation keeps it and gains the generated annotation.
        Assert.assertTrue(modifiedSource.contains("@Labelled"),
                "Expected the existing class-level annotation to be preserved");
        Assert.assertTrue(modifiedSource.contains("@ai:AgentMetadata {tools: [\"someTool\"]}"),
                "Expected the generated annotation to be appended alongside the existing annotation");
    }

    private static int countOccurrences(String source, String target) {
        int count = 0;
        int index = source.indexOf(target);
        while (index >= 0) {
            count += 1;
            index = source.indexOf(target, index + target.length());
        }
        return count;
    }

    private static String getModifiedSourceForProject(String packagePath) {
        BuildProject project = BuildProject.load(getEnvironmentBuilder(), RESOURCE_DIRECTORY.resolve(packagePath));
        DiagnosticResult diagnosticResult = project.currentPackage().runCodeGenAndModifyPlugins();
        Assert.assertEquals(diagnosticResult.errorCount(), 0,
                "Expected no compilation errors in the " + packagePath + " source: " + diagnosticResult.errors());
        return getModifiedSource(project);
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
