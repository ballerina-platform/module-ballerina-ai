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

import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.ModuleMemberDeclarationNode;
import io.ballerina.compiler.syntax.tree.ModulePartNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
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
import java.util.ArrayList;
import java.util.List;

/**
 * Tests the module {@code init} function that the compiler plugin generates to initialize module-level agents.
 * <p>
 * The function must be generated only when there is a module-level agent declaration to desugar. Generating it
 * unconditionally leaves dead code in every module that merely defines an agent class or an agent tool, and that code
 * is indistinguishable from a user-written entrypoint to any other compiler plugin analyzing the module.
 */
public class GeneratedInitFunctionTest {

    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources",
            "ballerina_sources", "init_function_tests").toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime").toAbsolutePath();

    @Test
    public void testNoInitFunctionGeneratedWithoutModuleLevelAgents() {
        List<FunctionDefinitionNode> initFunctions = moduleLevelInitFunctions("01_agent_class_only");
        Assert.assertTrue(initFunctions.isEmpty(),
                "No module init function should be generated for a module without module-level agent declarations, "
                        + "but found: " + initFunctions.stream().map(Object::toString).toList());
    }

    @Test
    public void testInitFunctionGeneratedForModuleLevelAgents() {
        List<FunctionDefinitionNode> initFunctions = moduleLevelInitFunctions("02_module_level_agent");
        Assert.assertEquals(initFunctions.size(), 1,
                "Exactly one module init function should be generated for a module-level agent declaration");
        String initFunction = initFunctions.getFirst().toSourceCode();
        Assert.assertTrue(initFunction.contains("supportAgent = check new"),
                "The generated init function should initialize the module-level agent, but was: " + initFunction);
    }

    // Returns the module-level `init` functions of the default module after code modification. Object methods are
    // OBJECT_METHOD_DEFINITION nodes and are not module members, so a class's own `init` method is not counted.
    private static List<FunctionDefinitionNode> moduleLevelInitFunctions(String packagePath) {
        BuildProject project = BuildProject.load(getEnvironmentBuilder(), RESOURCE_DIRECTORY.resolve(packagePath));
        DiagnosticResult diagnosticResult = project.currentPackage().runCodeGenAndModifyPlugins();
        Assert.assertEquals(diagnosticResult.errorCount(), 0,
                "Expected no compilation errors in the " + packagePath + " source: " + diagnosticResult.errors());

        List<FunctionDefinitionNode> initFunctions = new ArrayList<>();
        Module module = project.currentPackage().getDefaultModule();
        for (DocumentId documentId : module.documentIds()) {
            Document document = module.document(documentId);
            ModulePartNode root = (ModulePartNode) document.syntaxTree().rootNode();
            for (ModuleMemberDeclarationNode member : root.members()) {
                if (member.kind() != SyntaxKind.FUNCTION_DEFINITION) {
                    continue;
                }
                FunctionDefinitionNode function = (FunctionDefinitionNode) member;
                if ("init".equals(function.functionName().text().trim())) {
                    initFunctions.add(function);
                }
            }
        }
        return initFunctions;
    }

    private static ProjectEnvironmentBuilder getEnvironmentBuilder() {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(DISTRIBUTION_PATH).build();
        return ProjectEnvironmentBuilder.getBuilder(environment);
    }
}
