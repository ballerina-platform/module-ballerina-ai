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
import io.ballerina.compiler.api.symbols.AnnotationSymbol;
import io.ballerina.compiler.api.symbols.FunctionSymbol;
import io.ballerina.compiler.api.symbols.FunctionTypeSymbol;
import io.ballerina.compiler.api.symbols.ModuleSymbol;
import io.ballerina.compiler.api.symbols.ParameterSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.SymbolKind;
import io.ballerina.compiler.api.symbols.TypeDefinitionSymbol;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.api.symbols.UnionTypeSymbol;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.IdentifierToken;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.NodeList;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.tools.diagnostics.Location;

import java.util.List;
import java.util.Optional;

import static io.ballerina.openapi.service.mapper.utils.MapperCommonUtils.containErrors;
import static io.ballerina.stdlib.ai.plugin.OpenAPIGenerator.isAiAgentService;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.INVALID_HEADERS_PARAMETER_TYPE;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.INVALID_PAYLOAD_PARAMETER_TYPE;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.INVALID_RESOURCE_PARAMETER_COUNT;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.INVALID_RESOURCE_RETURN_TYPE;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.MISSING_CHAT_RESOURCE;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.MISSING_PAYLOAD_ANNOTATION;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.UNSUPPORTED_RESOURCE;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.getDiagnostic;

/**
 * Validates the {@code chat} and {@code decision} resources of a service attached to an {@code ai:Listener}.
 * {@code ai:ChatService} no longer pins any of this down at the type level - it's just {@code *http:Service;} -
 * so a resource can take an {@code http:Headers} parameter, or any other shape, without ever being a breaking
 * change for an existing implementation. That flexibility means the compiler can no longer catch these mistakes
 * through ordinary type conformance, so this task checks them directly, resolving the actual types involved
 * through the semantic model rather than comparing source text (which would miss an aliased import, e.g.
 * {@code import ballerina/http as h;} with {@code @h:Payload}):
 * <ul>
 * <li>the service must declare a {@code post chat} resource, since nothing else starts a run;</li>
 * <li>a {@code post chat} or {@code post decision} resource must declare one or two parameters - the only
 * values the native dispatcher can ever supply;</li>
 * <li>its first parameter must carry {@code @http:Payload} and accept the value the dispatcher actually sends
 * - {@code ai:ChatReqMessage} for {@code chat}, {@code ai:DecisionMessage} for {@code decision};</li>
 * <li>its second parameter, if present, must accept the {@code http:Headers} value the dispatcher sends;</li>
 * <li>its return type must be assignable to {@code ai:ChatRespMessage|error}, since that's what the native
 * adaptor and {@code toResponse} both assume;</li>
 * <li>any other resource is flagged, since the dispatcher only ever looks up a resource named exactly
 * {@code chat} or {@code decision} with the {@code post} accessor - anything else compiles but is never
 * reached.</li>
 * </ul>
 */
public class ChatResourceValidationTask implements AnalysisTask<SyntaxNodeAnalysisContext> {

    private static final String POST_ACCESSOR = "post";
    private static final String CHAT_RESOURCE_NAME = "chat";
    private static final String DECISION_RESOURCE_NAME = "decision";
    private static final String BALLERINA_ORG = "ballerina";
    private static final String AI_MODULE = "ai";
    private static final String HTTP_MODULE = "http";
    private static final String EMPTY_VERSION = "";
    private static final String CHAT_REQ_MESSAGE = "ChatReqMessage";
    private static final String DECISION_MESSAGE = "DecisionMessage";
    private static final String CHAT_RESP_MESSAGE = "ChatRespMessage";
    private static final String PAYLOAD_ANNOTATION_NAME = "Payload";
    private static final String HEADERS_TYPE_NAME = "Headers";
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
                validateResource(context, semanticModel, resourceNode, pathSegment, CHAT_REQ_MESSAGE);
            } else if (DECISION_RESOURCE_NAME.equals(pathSegment)) {
                validateResource(context, semanticModel, resourceNode, pathSegment, DECISION_MESSAGE);
            } else {
                context.reportDiagnostic(getDiagnostic(UNSUPPORTED_RESOURCE, resourceNode.location()));
            }
        }

        if (!hasChatResource) {
            context.reportDiagnostic(getDiagnostic(MISSING_CHAT_RESOURCE, serviceNode.location()));
        }
    }

    private static void validateResource(SyntaxNodeAnalysisContext context, SemanticModel semanticModel,
                                         FunctionDefinitionNode resourceNode, String pathSegment,
                                         String expectedPayloadTypeName) {
        String resourceLabel = POST_ACCESSOR + " " + pathSegment;

        // Arity first: purely syntactic, cheap, and catches the common mistake without needing a
        // resolvable semantic model.
        int declared = resourceNode.functionSignature().parameters().size();
        if (declared < MIN_SUPPORTED_PARAMETERS || declared > MAX_SUPPORTED_PARAMETERS) {
            context.reportDiagnostic(getDiagnostic(INVALID_RESOURCE_PARAMETER_COUNT, resourceNode.location(),
                    resourceLabel, declared));
            return;
        }

        Optional<Symbol> symbol = semanticModel.symbol(resourceNode);
        if (symbol.isEmpty() || symbol.get().kind() != SymbolKind.RESOURCE_METHOD
                || !(symbol.get() instanceof FunctionSymbol resourceSymbol)) {
            return;
        }
        FunctionTypeSymbol functionType = resourceSymbol.typeDescriptor();
        List<ParameterSymbol> parameters = functionType.params().orElse(List.of());
        if (parameters.size() != declared) {
            // The semantic model disagrees with the syntactic count (e.g. a rest parameter) - the
            // arity check above already covers the shape that matters, so don't risk an index
            // mismatch chasing a case this task isn't meant to classify further.
            return;
        }

        Location resourceLocation = resourceNode.location();
        validatePayloadParameter(context, semanticModel, parameters.get(0), resourceLabel, resourceLocation,
                expectedPayloadTypeName);
        if (declared == MAX_SUPPORTED_PARAMETERS) {
            validateHeadersParameter(context, semanticModel, parameters.get(1), resourceLabel, resourceLocation);
        }
        validateReturnType(context, semanticModel, resourceSymbol, resourceLabel, resourceLocation);
    }

    private static void validatePayloadParameter(SyntaxNodeAnalysisContext context, SemanticModel semanticModel,
                                                  ParameterSymbol payloadParameter, String resourceLabel,
                                                  Location fallbackLocation, String expectedPayloadTypeName) {
        Location location = payloadParameter.getLocation().orElse(fallbackLocation);
        if (!hasAnnotation(payloadParameter, HTTP_MODULE, PAYLOAD_ANNOTATION_NAME)) {
            context.reportDiagnostic(getDiagnostic(MISSING_PAYLOAD_ANNOTATION, location, resourceLabel));
            return;
        }
        Optional<TypeSymbol> expectedType = resolveType(semanticModel, AI_MODULE, expectedPayloadTypeName);
        if (expectedType.isEmpty()) {
            return;
        }
        TypeSymbol declaredType = payloadParameter.typeDescriptor();
        if (!expectedType.get().assignableTo(declaredType)) {
            context.reportDiagnostic(getDiagnostic(INVALID_PAYLOAD_PARAMETER_TYPE, location, resourceLabel,
                    expectedPayloadTypeName, declaredType.signature()));
        }
    }

    private static void validateHeadersParameter(SyntaxNodeAnalysisContext context, SemanticModel semanticModel,
                                                 ParameterSymbol headersParameter, String resourceLabel,
                                                 Location fallbackLocation) {
        Optional<TypeSymbol> headersType = resolveType(semanticModel, HTTP_MODULE, HEADERS_TYPE_NAME);
        if (headersType.isEmpty()) {
            return;
        }
        TypeSymbol declaredType = headersParameter.typeDescriptor();
        if (!headersType.get().assignableTo(declaredType)) {
            Location location = headersParameter.getLocation().orElse(fallbackLocation);
            context.reportDiagnostic(getDiagnostic(INVALID_HEADERS_PARAMETER_TYPE, location, resourceLabel,
                    declaredType.signature()));
        }
    }

    private static void validateReturnType(SyntaxNodeAnalysisContext context, SemanticModel semanticModel,
                                           FunctionSymbol resourceSymbol, String resourceLabel,
                                           Location fallbackLocation) {
        Optional<TypeSymbol> returnType = resourceSymbol.typeDescriptor().returnTypeDescriptor();
        if (returnType.isEmpty()) {
            return;
        }
        Optional<TypeSymbol> chatRespMessageType = resolveType(semanticModel, AI_MODULE, CHAT_RESP_MESSAGE);
        if (chatRespMessageType.isEmpty()) {
            return;
        }
        TypeSymbol errorType = semanticModel.types().ERROR;
        if (!isAssignableToEither(returnType.get(), chatRespMessageType.get(), errorType)) {
            Location location = resourceSymbol.getLocation().orElse(fallbackLocation);
            context.reportDiagnostic(getDiagnostic(INVALID_RESOURCE_RETURN_TYPE, location, resourceLabel,
                    returnType.get().signature()));
        }
    }

    // A union return type (the common case, e.g. `ChatRespMessage|error`) only needs every member to land in
    // one of the two buckets; a non-union return type just needs to land in one of them directly.
    private static boolean isAssignableToEither(TypeSymbol type, TypeSymbol first, TypeSymbol second) {
        if (type instanceof UnionTypeSymbol union) {
            return union.memberTypeDescriptors().stream()
                    .allMatch(member -> member.subtypeOf(first) || member.subtypeOf(second));
        }
        return type.subtypeOf(first) || type.subtypeOf(second);
    }

    private static boolean hasAnnotation(ParameterSymbol parameter, String moduleName, String annotationName) {
        for (AnnotationSymbol annotation : parameter.annotations()) {
            Optional<ModuleSymbol> module = annotation.getModule();
            if (module.isEmpty()) {
                continue;
            }
            boolean isExpectedModule = BALLERINA_ORG.equals(module.get().id().orgName())
                    && moduleName.equals(module.get().id().moduleName());
            boolean isExpectedName = annotation.getName().map(annotationName::equals).orElse(false);
            if (isExpectedModule && isExpectedName) {
                return true;
            }
        }
        return false;
    }

    private static Optional<TypeSymbol> resolveType(SemanticModel semanticModel, String moduleName,
                                                     String typeName) {
        Optional<Symbol> symbol = semanticModel.types()
                .getTypeByName(BALLERINA_ORG, moduleName, EMPTY_VERSION, typeName);
        if (symbol.isEmpty()) {
            return Optional.empty();
        }
        // A type defined with `type X ...` resolves to a TypeDefinitionSymbol, whose typeDescriptor() gives
        // the actual type (e.g. ai:ChatReqMessage, a record). A type backed by a class instead, such as
        // `http:Headers`, resolves directly to a ClassSymbol, which is itself a TypeSymbol.
        Symbol resolved = symbol.get();
        if (resolved instanceof TypeDefinitionSymbol typeDefinition) {
            return Optional.of(typeDefinition.typeDescriptor());
        }
        if (resolved instanceof TypeSymbol typeSymbol) {
            return Optional.of(typeSymbol);
        }
        return Optional.empty();
    }

    private static String singlePathSegment(NodeList<Node> resourcePath) {
        if (resourcePath.size() != 1 || resourcePath.get(0).kind() != SyntaxKind.IDENTIFIER_TOKEN) {
            return null;
        }
        return ((IdentifierToken) resourcePath.get(0)).text().trim();
    }
}
