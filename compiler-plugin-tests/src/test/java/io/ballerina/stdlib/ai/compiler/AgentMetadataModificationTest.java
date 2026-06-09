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
        // The object method tool, the module-level function tool, and the inline ToolConfig tool — with the
        // `@display` label/icon read syntactically (self.method) and via the symbol API (module function).
        Assert.assertTrue(modifiedSource.contains(
                        "{name: \"createSchedule\", kind: ai:FUNCTION_TOOL, label: \"Create Schedule\"}"),
                "Expected the object method tool with its @display label (read syntactically)");
        Assert.assertTrue(modifiedSource.contains(
                        "{name: \"coordinateSpeakers\", kind: ai:FUNCTION_TOOL, label: \"Coordinate Speakers\", "
                                + "icon: \"speakers.png\"}"),
                "Expected the module-level function tool with its @display label and icon (read via symbol)");
        Assert.assertTrue(modifiedSource.contains("{name: \"searchTool\", kind: ai:FUNCTION_TOOL}"),
                "Expected the inline ToolConfig tool with no display info");
    }

    @Test
    public void testAgentMetadataAnnotationWithToolKit() {
        String modifiedSource = getModifiedSourceForProject("02_custom_agent_with_toolkit");
        Assert.assertTrue(modifiedSource.contains("{name: \"getDiscounts\", kind: ai:FUNCTION_TOOL}"),
                "Expected the function tool to be listed");
        Assert.assertTrue(modifiedSource.contains("{name: \"toolKit\", kind: ai:TOOLKIT}"),
                "Expected the non-MCP toolkit to be listed by its variable name with kind TOOLKIT");
        Assert.assertTrue(modifiedSource.contains(
                        "@ai:AgentMetadata {tools: [{name: \"toolKit\", kind: ai:TOOLKIT}]}"),
                "Expected the toolkit-only agent to list just the toolkit");
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
        Assert.assertTrue(modifiedSource.contains(
                        "@ai:AgentMetadata {tools: [{name: \"manuallyListedTool\", kind: ai:FUNCTION_TOOL}]}"),
                "Expected the user-written @ai:AgentMetadata annotation to be preserved");
        Assert.assertFalse(agentMetadataAnnotation(modifiedSource).contains("reportWeather"),
                "The generated tool list must not overwrite the user-written annotation");
    }

    @Test
    public void testAgentMetadataAnnotationWithAliasedImport() {
        String modifiedSource = getModifiedSourceForProject("05_aliased_import");
        Assert.assertTrue(modifiedSource.contains(
                        "@intelligence:AgentMetadata {tools: [{name: \"answerMath\", kind: " +
                                "intelligence:FUNCTION_TOOL}]}"),
                "Expected the generated annotation and enum members to use the aliased ballerina/ai prefix");
    }

    @Test
    public void testAgentMetadataAnnotationWithExplicitNewQualifiedAndMcp() {
        String modifiedSource = getModifiedSourceForProject("06_explicit_new_and_qualified");
        Assert.assertTrue(modifiedSource.contains("{name: \"localTool\", kind: ai:FUNCTION_TOOL}"),
                "Expected the module-level function tool");
        // The cross-module tool's @display label is read across the module boundary (const annotation).
        Assert.assertTrue(modifiedSource.contains(
                        "{name: \"remoteLookup\", kind: ai:FUNCTION_TOOL, label: \"Remote Lookup\"}"),
                "Expected the qualified cross-module tool with its @display label read across modules");
        Assert.assertTrue(modifiedSource.contains("{name: \"inlineNamed\", kind: ai:FUNCTION_TOOL}"),
                "Expected the inline ToolConfig tool");
        Assert.assertTrue(modifiedSource.contains("{name: \"weatherMcp\", kind: ai:MCP_TOOLKIT}"),
                "Expected the MCP toolkit variable, named after the variable, with kind MCP_TOOLKIT");
        Assert.assertTrue(modifiedSource.contains("{name: \"McpToolKit\", kind: ai:MCP_TOOLKIT}"),
                "Expected the inline MCP toolkit, named after its type, with kind MCP_TOOLKIT");
        String annotation = agentMetadataAnnotation(modifiedSource);
        Assert.assertFalse(annotation.contains("fromVariable"),
                "A ToolConfig variable cannot be resolved statically and must be skipped");
        Assert.assertFalse(annotation.contains("computed"),
                "An inline ToolConfig with a non-literal name must be skipped");
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
        Assert.assertTrue(modifiedSource.contains(
                        "@ai:AgentMetadata {tools: [{name: \"someTool\", kind: ai:FUNCTION_TOOL}]}"),
                "Expected the generated annotation to be appended alongside the existing annotation");
    }

    // Returns the first generated `@ai:AgentMetadata {tools: [...]}` annotation, so negative assertions can be
    // scoped to
    // the annotation rather than the whole document (where a skipped tool's name may still appear in the source).
    private static String agentMetadataAnnotation(String source) {
        int start = source.indexOf("AgentMetadata {tools: [");
        if (start < 0) {
            return "";
        }
        int end = source.indexOf("]}", start);
        return end < 0 ? source.substring(start) : source.substring(start, end);
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
