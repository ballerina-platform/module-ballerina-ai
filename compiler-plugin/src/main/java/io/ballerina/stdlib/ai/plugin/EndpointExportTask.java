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

package io.ballerina.stdlib.ai.plugin;

import io.ballerina.compiler.api.SemanticModel;
import io.ballerina.compiler.api.symbols.ServiceDeclarationSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SyntaxTree;
import io.ballerina.projects.Module;
import io.ballerina.projects.Project;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.servers.ServerVariable;
import io.swagger.v3.oas.models.servers.ServerVariables;

import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static io.ballerina.openapi.service.mapper.Constants.HYPHEN;
import static io.ballerina.openapi.service.mapper.Constants.OPENAPI_SUFFIX;
import static io.ballerina.openapi.service.mapper.Constants.SLASH;
import static io.ballerina.openapi.service.mapper.Constants.YAML_EXTENSION;
import static io.ballerina.openapi.service.mapper.utils.MapperCommonUtils.containErrors;
import static io.ballerina.openapi.service.mapper.utils.MapperCommonUtils.getNormalizedFileName;
import static io.ballerina.openapi.service.mapper.utils.MapperCommonUtils.unescapeIdentifier;
import static io.ballerina.stdlib.ai.plugin.OpenAPIGenerator.extractServiceNodes;
import static io.ballerina.stdlib.ai.plugin.OpenAPIGenerator.generateChatServiceSchema;
import static io.ballerina.stdlib.ai.plugin.OpenAPIGenerator.UNDERSCORE;
import static io.ballerina.stdlib.ai.plugin.OpenAPIGenerator.isAiAgentService;
import static io.ballerina.stdlib.ai.plugin.OpenAPIGenerator.writeOpenAPIYaml;

/**
 * Analysis task that extracts the endpoint metadata of each AI agent chat service when the
 * {@code --export-endpoints} build option is enabled. The chat service OpenAPI specification is written to the
 * {@code target/artifact} directory, and the endpoint is collected for {@link EndpointMetadataTask} to publish
 * through Ballerina lang.
 */
public class EndpointExportTask implements AnalysisTask<SyntaxNodeAnalysisContext> {
    private static final String ARTIFACT = "artifact";
    private static final String REST = "REST";
    private static final String PORT = "port";
    private static final String BAL_EXTENSION = ".bal";

    private final List<Endpoint> endpoints;

    EndpointExportTask(List<Endpoint> endpoints) {
        this.endpoints = endpoints;
    }

    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        Project project = context.currentPackage().project();
        if (!project.buildOptions().exportEndpoints() || isInTestSource(context)) {
            return;
        }
        SemanticModel semanticModel = context.semanticModel();
        ServiceDeclarationNode serviceNode = (ServiceDeclarationNode) context.node();
        if (containErrors(semanticModel.diagnostics()) || !isAiAgentService(serviceNode, semanticModel)) {
            return;
        }
        Optional<Symbol> serviceSymbol = semanticModel.symbol(serviceNode);
        if (serviceSymbol.isEmpty() || !(serviceSymbol.get() instanceof ServiceDeclarationSymbol)) {
            return;
        }

        List<Diagnostic> diagnostics = new ArrayList<>();
        OpenAPI chatServiceSchema = generateChatServiceSchema(serviceNode, semanticModel, project, diagnostics);

        SyntaxTree syntaxTree = context.syntaxTree();
        Map<Integer, String> services = new HashMap<>();
        extractServiceNodes(syntaxTree.rootNode(), services, semanticModel);
        String fileName = constructSchemaFileName(syntaxTree, services, serviceSymbol.get());
        Path artifactDir = project.targetDir().resolve(ARTIFACT);
        Optional<String> schemaFileName = writeOpenAPIYaml(artifactDir, chatServiceSchema, fileName, diagnostics);

        if (schemaFileName.isPresent()) {
            String basePath = getBasePath(serviceNode);
            endpoints.add(new Endpoint(basePath, getPort(chatServiceSchema), basePath, REST, schemaFileName.get()));
        }
        diagnostics.forEach(context::reportDiagnostic);
    }

    /**
     * Constructs the OpenAPI specification file name in the {@code <bal file>_<base path>_openapi.yaml} form used by
     * the HTTP module, so that the specifications of AI agent and HTTP services share one naming scheme in the
     * artifact directory.
     *
     * @param syntaxTree    the syntax tree of the document containing the service
     * @param services      the base path of each AI agent service in the document keyed by symbol hash code
     * @param serviceSymbol the symbol of the service
     * @return the file name of the OpenAPI specification
     */
    private static String constructSchemaFileName(SyntaxTree syntaxTree, Map<Integer, String> services,
                                                  Symbol serviceSymbol) {
        String filePath = syntaxTree.filePath().replace(SLASH, UNDERSCORE);
        String balFileName = filePath.endsWith(BAL_EXTENSION)
                ? filePath.substring(0, filePath.length() - BAL_EXTENSION.length()) : filePath;
        String serviceName = services.get(serviceSymbol.hashCode());
        String fileName = serviceName == null ? "" : getNormalizedFileName(serviceName);
        if (fileName.equals(SLASH)) {
            return balFileName + OPENAPI_SUFFIX + YAML_EXTENSION;
        }
        if (fileName.isBlank() || fileName.contains(HYPHEN) && fileName.split(HYPHEN)[0].equals(SLASH)) {
            return balFileName + UNDERSCORE + serviceSymbol.hashCode() + OPENAPI_SUFFIX + YAML_EXTENSION;
        }
        return balFileName + UNDERSCORE + fileName + OPENAPI_SUFFIX + YAML_EXTENSION;
    }

    private static boolean isInTestSource(SyntaxNodeAnalysisContext context) {
        Module currentModule = context.currentPackage().module(context.moduleId());
        return currentModule.testDocumentIds().contains(context.documentId());
    }

    private static int getPort(OpenAPI openAPI) {
        // ServersMapper always resolves the servers of a chat service to a single server
        ServerVariables variables = openAPI.getServers().getFirst().getVariables();
        ServerVariable portVariable = variables == null ? null : variables.get(PORT);
        if (portVariable == null || portVariable.getDefault() == null) {
            return 0;
        }
        try {
            return Integer.parseInt(portVariable.getDefault());
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    private static String getBasePath(ServiceDeclarationNode serviceNode) {
        StringBuilder basePath = new StringBuilder();
        for (Node node : serviceNode.absoluteResourcePath()) {
            basePath.append(unescapeIdentifier(node.toString()));
        }
        return basePath.toString().trim();
    }
}
