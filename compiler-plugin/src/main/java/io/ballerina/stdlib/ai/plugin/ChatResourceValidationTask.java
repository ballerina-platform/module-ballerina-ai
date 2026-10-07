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
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.IdentifierToken;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.NodeList;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.tools.diagnostics.Diagnostic;

import static io.ballerina.openapi.service.mapper.utils.MapperCommonUtils.containErrors;
import static io.ballerina.stdlib.ai.plugin.OpenAPIGenerator.isAiAgentService;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.MISSING_CHAT_RESOURCE;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.getDiagnostic;

/**
 * Validates that every service attached to an {@code ai:Listener} declares a {@code post chat} resource.
 * {@code ai:ChatService} no longer requires {@code chat} at the type level - only {@code *http:Service;} - so a
 * resource with an {@code http:Headers} parameter (or any other shape) is never a breaking change for an existing
 * implementation. That flexibility means the compiler can no longer catch a missing {@code chat} resource through
 * ordinary type conformance, so this task restores that check directly.
 */
public class ChatResourceValidationTask implements AnalysisTask<SyntaxNodeAnalysisContext> {

    private static final String POST_ACCESSOR = "post";
    private static final String CHAT_RESOURCE_NAME = "chat";

    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        SemanticModel semanticModel = context.semanticModel();
        if (containErrors(semanticModel.diagnostics())) {
            return;
        }
        ServiceDeclarationNode serviceNode = (ServiceDeclarationNode) context.node();
        if (!isAiAgentService(serviceNode, semanticModel) || hasChatResource(serviceNode)) {
            return;
        }
        Diagnostic diagnostic = getDiagnostic(MISSING_CHAT_RESOURCE, serviceNode.location());
        context.reportDiagnostic(diagnostic);
    }

    private static boolean hasChatResource(ServiceDeclarationNode serviceNode) {
        for (Node member : serviceNode.members()) {
            if (member.kind() != SyntaxKind.RESOURCE_ACCESSOR_DEFINITION) {
                continue;
            }
            FunctionDefinitionNode resourceNode = (FunctionDefinitionNode) member;
            if (!POST_ACCESSOR.equals(resourceNode.functionName().text().trim())) {
                continue;
            }
            if (isChatPath(resourceNode.relativeResourcePath())) {
                return true;
            }
        }
        return false;
    }

    private static boolean isChatPath(NodeList<Node> resourcePath) {
        return resourcePath.size() == 1 && resourcePath.get(0).kind() == SyntaxKind.IDENTIFIER_TOKEN
                && CHAT_RESOURCE_NAME.equals(((IdentifierToken) resourcePath.get(0)).text().trim());
    }
}
