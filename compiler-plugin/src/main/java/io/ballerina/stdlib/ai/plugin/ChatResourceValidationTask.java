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
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.DefaultableParameterNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.IdentifierToken;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.NodeList;
import io.ballerina.compiler.syntax.tree.ParameterNode;
import io.ballerina.compiler.syntax.tree.RequiredParameterNode;
import io.ballerina.compiler.syntax.tree.RestParameterNode;
import io.ballerina.compiler.syntax.tree.SeparatedNodeList;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;

import static io.ballerina.openapi.service.mapper.utils.MapperCommonUtils.containErrors;
import static io.ballerina.stdlib.ai.plugin.OpenAPIGenerator.isAiAgentService;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.INVALID_HEADERS_PARAMETER_TYPE;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.INVALID_RESOURCE_PARAMETER_COUNT;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.MISSING_CHAT_RESOURCE;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.MISSING_PAYLOAD_ANNOTATION;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.UNSUPPORTED_RESOURCE;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.getDiagnostic;

/**
 * Validates the resources of a service attached to an {@code ai:Listener}. {@code ai:ChatService} no longer pins
 * any of this down at the type level - it's just {@code *http:Service;} - so a resource can take an
 * {@code http:Headers} parameter, or any other shape, without ever being a breaking change for an existing
 * implementation. That flexibility means the compiler can no longer catch these mistakes through ordinary type
 * conformance, so this task checks them directly:
 * <ul>
 * <li>the service must declare a {@code post chat} resource, since nothing else starts a run;</li>
 * <li>a {@code post chat} or {@code post decision} resource must declare one or two parameters - the only
 * values the native dispatcher can ever supply - with its first parameter carrying {@code @http:Payload}
 * (or the dispatcher's payload lands in a parameter Ballerina bound a completely different way, e.g. as a
 * query parameter) and its second parameter, if present, declared as exactly {@code http:Headers};</li>
 * <li>any other resource is flagged, since the dispatcher only ever looks up a resource named exactly
 * {@code chat} or {@code decision} with the {@code post} accessor - anything else compiles but is never
 * reached.</li>
 * </ul>
 */
public class ChatResourceValidationTask implements AnalysisTask<SyntaxNodeAnalysisContext> {

    private static final String POST_ACCESSOR = "post";
    private static final String CHAT_RESOURCE_NAME = "chat";
    private static final String DECISION_RESOURCE_NAME = "decision";
    private static final String PAYLOAD_ANNOTATION = "http:Payload";
    private static final String HEADERS_TYPE = "http:Headers";
    private static final int MIN_SUPPORTED_PARAMETERS = 1;
    private static final int MAX_SUPPORTED_PARAMETERS = 2;

    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        SemanticModel semanticModel = context.semanticModel();
        if (containErrors(semanticModel.diagnostics())) {
            return;
        }
        ServiceDeclarationNode serviceNode = (ServiceDeclarationNode) context.node();
        if (!isAiAgentService(serviceNode, semanticModel)) {
            return;
        }

        boolean hasChatResource = false;
        for (Node member : serviceNode.members()) {
            if (member.kind() != SyntaxKind.RESOURCE_ACCESSOR_DEFINITION) {
                continue;
            }
            FunctionDefinitionNode resourceNode = (FunctionDefinitionNode) member;
            boolean isPost = POST_ACCESSOR.equals(resourceNode.functionName().text().trim());
            String pathSegment = isPost ? singlePathSegment(resourceNode.relativeResourcePath()) : null;
            if (CHAT_RESOURCE_NAME.equals(pathSegment)) {
                hasChatResource = true;
                validateResourceParameters(context, resourceNode, pathSegment);
            } else if (DECISION_RESOURCE_NAME.equals(pathSegment)) {
                validateResourceParameters(context, resourceNode, pathSegment);
            } else {
                context.reportDiagnostic(getDiagnostic(UNSUPPORTED_RESOURCE, resourceNode.location()));
            }
        }

        if (!hasChatResource) {
            context.reportDiagnostic(getDiagnostic(MISSING_CHAT_RESOURCE, serviceNode.location()));
        }
    }

    private static void validateResourceParameters(SyntaxNodeAnalysisContext context,
                                                   FunctionDefinitionNode resourceNode, String pathSegment) {
        String resourceLabel = POST_ACCESSOR + " " + pathSegment;
        SeparatedNodeList<ParameterNode> parameters = resourceNode.functionSignature().parameters();
        int declared = parameters.size();
        if (declared < MIN_SUPPORTED_PARAMETERS || declared > MAX_SUPPORTED_PARAMETERS) {
            context.reportDiagnostic(getDiagnostic(INVALID_RESOURCE_PARAMETER_COUNT, resourceNode.location(),
                    resourceLabel, declared));
            return;
        }

        ParameterNode payloadParameter = parameters.get(0);
        if (!hasPayloadAnnotation(payloadParameter)) {
            context.reportDiagnostic(getDiagnostic(MISSING_PAYLOAD_ANNOTATION, payloadParameter.location(),
                    resourceLabel));
        }

        if (declared == MAX_SUPPORTED_PARAMETERS) {
            ParameterNode headersParameter = parameters.get(1);
            String headersType = parameterTypeText(headersParameter);
            if (!HEADERS_TYPE.equals(headersType)) {
                context.reportDiagnostic(getDiagnostic(INVALID_HEADERS_PARAMETER_TYPE, headersParameter.location(),
                        resourceLabel, headersType));
            }
        }
    }

    private static boolean hasPayloadAnnotation(ParameterNode parameterNode) {
        NodeList<AnnotationNode> annotations = parameterAnnotations(parameterNode);
        if (annotations == null) {
            return false;
        }
        for (AnnotationNode annotation : annotations) {
            if (PAYLOAD_ANNOTATION.equals(annotation.annotReference().toString().trim())) {
                return true;
            }
        }
        return false;
    }

    private static NodeList<AnnotationNode> parameterAnnotations(ParameterNode parameterNode) {
        if (parameterNode instanceof RequiredParameterNode p) {
            return p.annotations();
        }
        if (parameterNode instanceof DefaultableParameterNode p) {
            return p.annotations();
        }
        if (parameterNode instanceof RestParameterNode p) {
            return p.annotations();
        }
        return null;
    }

    private static String parameterTypeText(ParameterNode parameterNode) {
        Node typeName = null;
        if (parameterNode instanceof RequiredParameterNode p) {
            typeName = p.typeName();
        } else if (parameterNode instanceof DefaultableParameterNode p) {
            typeName = p.typeName();
        } else if (parameterNode instanceof RestParameterNode p) {
            typeName = p.typeName();
        }
        return typeName == null ? null : typeName.toString().trim();
    }

    private static String singlePathSegment(NodeList<Node> resourcePath) {
        if (resourcePath.size() != 1 || resourcePath.get(0).kind() != SyntaxKind.IDENTIFIER_TOKEN) {
            return null;
        }
        return ((IdentifierToken) resourcePath.get(0)).text().trim();
    }
}
