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

package io.ballerina.stdlib.ai.plugin;

import io.ballerina.compiler.api.SemanticModel;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.VariableSymbol;
import io.ballerina.compiler.syntax.tree.BasicLiteralNode;
import io.ballerina.compiler.syntax.tree.BracedExpressionNode;
import io.ballerina.compiler.syntax.tree.CheckExpressionNode;
import io.ballerina.compiler.syntax.tree.ExplicitNewExpressionNode;
import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.FunctionArgumentNode;
import io.ballerina.compiler.syntax.tree.ImplicitNewExpressionNode;
import io.ballerina.compiler.syntax.tree.ListenerDeclarationNode;
import io.ballerina.compiler.syntax.tree.MappingConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.NamedArgumentNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.ParenthesizedArgList;
import io.ballerina.compiler.syntax.tree.PositionalArgumentNode;
import io.ballerina.compiler.syntax.tree.QualifiedNameReferenceNode;
import io.ballerina.compiler.syntax.tree.SeparatedNodeList;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.openapi.service.mapper.utils.MapperCommonUtils;
import io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.Location;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.servers.Server;
import io.swagger.v3.oas.models.servers.ServerVariable;
import io.swagger.v3.oas.models.servers.ServerVariables;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

import static io.ballerina.stdlib.ai.plugin.OpenAPIGenerator.NullLocation;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.UNABLE_TO_OBTAIN_VALID_SERVER_PORT;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.UNABLE_TO_OBTAIN_VALID_SERVER_PORT_FROM_EXPRESSION;
import static io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic.getDiagnostic;

/**
 * Maps Ballerina service listeners to OpenAPI {@link Server} definitions by extracting host and port information.
 * Modifies the given OpenAPI instance by adding the mapped server details.
 */
public class ServersMapper {
    private static final String SERVER = "server";
    private static final String PORT = "port";
    private static final String HOST_FIELD_NAME = "host";
    private static final String LISTEN_ON = "listenOn";
    private static final String DEFAULT_HTTP_PORT = "9090";
    private static final String PORT_443 = "443";
    private static final String HTTPS_LOCALHOST = "https://localhost";
    private static final String HTTP_LOCALHOST = "http://localhost";

    private final OpenAPI openAPI;
    private final Map<String, ListenerDeclarationNode> endpoints;
    private final ServiceDeclarationNode service;
    private final SemanticModel semanticModel;
    private final List<Diagnostic> diagnostics = new ArrayList<>();

    public ServersMapper(OpenAPI openAPI, Set<ListenerDeclarationNode> endpoints,
                         ServiceDeclarationNode service, SemanticModel semanticModel) {
        this.openAPI = openAPI;
        this.endpoints = mapEndpoints(endpoints);
        this.service = service;
        this.semanticModel = semanticModel;
    }

    private static Map<String, ListenerDeclarationNode> mapEndpoints(Set<ListenerDeclarationNode> nodes) {
        return nodes.stream()
                .collect(Collectors.toMap(node -> node.variableName().text(), Function.identity()));
    }

    public void setServers() {
        extractServersFromServiceExpressions();

        List<Server> servers = this.openAPI.getServers();
        if (!endpoints.isEmpty()) {
            for (ListenerDeclarationNode endpoint : endpoints.values()) {
                for (ExpressionNode expression : this.service.expressions()) {
                    addServerForEndpoint(servers, endpoint, expression);
                }
            }
        }

        if (isServerListEmpty()) {
            this.openAPI.setServers(Collections.singletonList(getDefaultServerWithBasePath(getServiceBasePath())));
        } else if (servers.size() > 1) {
            this.openAPI.setServers(Collections.singletonList(mergeServerEnums(servers)));
        }
    }

    private boolean isServerListEmpty() {
        return this.openAPI.getServers().isEmpty() || this.openAPI.getServers().stream()
                .allMatch(server -> server.getUrl() == null
                        && (server.getVariables() == null || server.getVariables().isEmpty()));
    }

    private void addServerForEndpoint(List<Server> servers, ListenerDeclarationNode endpoint, ExpressionNode expNode) {
        String endpointName = endpoint.variableName().text().trim();

        boolean matchesEndpoint = (expNode instanceof QualifiedNameReferenceNode qualifiedNameReferenceNode
                && qualifiedNameReferenceNode.identifier().text().trim().equals(endpointName))
                || expNode.toString().trim().equals(endpointName);

        if (matchesEndpoint) {
            servers.add(extractServer(endpoint, getServiceBasePath()));
        }
    }

    private static Server mergeServerEnums(List<Server> servers) {
        if (servers.isEmpty()) {
            return null;
        }

        Server mainServer = servers.getFirst();
        ServerVariables mainVars = mainServer.getVariables();
        ServerVariable hostVar = mainVars.get(SERVER);
        ServerVariable portVar = mainVars.get(PORT);

        if (servers.size() > 1) {
            List<Server> rotated = new ArrayList<>(servers);
            Collections.rotate(rotated, servers.size() - 1);

            for (Server server : rotated) {
                ServerVariables vars = server.getVariables();
                if (vars.get(SERVER) != null) {
                    hostVar.addEnumItem(vars.get(SERVER).getDefault());
                }
                if (vars.get(PORT) != null) {
                    portVar.addEnumItem(vars.get(PORT).getDefault());
                }
            }
        }
        return mainServer;
    }

    private Server extractServer(ListenerDeclarationNode endpoint, String basePath) {
        return generateServer(basePath, extractListenerArgList(endpoint.initializer()));
    }

    private static Optional<ParenthesizedArgList> extractParenthesizedArgList(Node expression) {
        return switch (expression.kind()) {
            case EXPLICIT_NEW_EXPRESSION ->
                    Optional.ofNullable(((ExplicitNewExpressionNode) expression).parenthesizedArgList());
            case IMPLICIT_NEW_EXPRESSION -> ((ImplicitNewExpressionNode) expression).parenthesizedArgList();
            default -> Optional.empty();
        };
    }

    /**
     * Extracts the constructor argument list from a listener initialization expression, unwrapping any
     * leading {@code check} and parenthesized expressions where present. This handles inline listener
     * expressions such as {@code new http:Listener(9091)}, {@code check new http:Listener(9091)} and
     * {@code check (new http:Listener(9091))}.
     *
     * @param node the listener initialization expression (or listener declaration initializer)
     * @return the parenthesized argument list if the expression is a {@code new} expression; otherwise empty
     */
    private static Optional<ParenthesizedArgList> extractListenerArgList(Node node) {
        Node expression = node;
        while (true) {
            if (expression.kind() == SyntaxKind.CHECK_EXPRESSION) {
                expression = ((CheckExpressionNode) expression).expression();
            } else if (expression.kind() == SyntaxKind.BRACED_EXPRESSION) {
                expression = ((BracedExpressionNode) expression).expression();
            } else {
                break;
            }
        }
        return extractParenthesizedArgList(expression);
    }

    private void extractServersFromServiceExpressions() {
        List<Server> servers = new ArrayList<>();
        String basePath = getServiceBasePath();

        for (ExpressionNode expression : this.service.expressions()) {
            if (expression.kind() == SyntaxKind.EXPLICIT_NEW_EXPRESSION) {
                ExplicitNewExpressionNode explicit = (ExplicitNewExpressionNode) expression;
                servers.add(generateServer(basePath, Optional.ofNullable(explicit.parenthesizedArgList())));
            }
        }
        openAPI.setServers(servers);
    }

    /**
     * Generates a {@link Server} object by analyzing the listener instantiation syntax and extracting
     * relevant host and port information. This method covers the majority of listener declaration
     * patterns used in Ballerina services and constructs the corresponding OpenAPI server definition.
     * <p>
     * Handles the following common listener initialization scenarios:
     * <ul>
     *   <li><code>ai:Listener l = new (6489)</code></li>
     *   <li><code>ai:Listener l = new (listenOn = 6489)</code></li>
     *   <li><code>ai:Listener l = new (httpListener)</code></li>
     *   <li><code>ai:Listener l = new (listenOn = httpListener)</code></li>
     *   <li><code>ai:Listener l = new (check http:getDefaultListener())</code></li>
     *   <li><code>ai:Listener l = new (listenOn = check http:getDefaultListener())</code></li>
     *   <li><code>http:Listener httpListener = new(9090)</code></li>
     *   <li><code>http:Listener httpListener = new(host = 9090)</code></li>
     *   <li><code>http:Listener httpListener = new(9090, host = "127.0.0.1")</code></li>
     *   <li><code>http:Listener httpListener = new(9090, { host: "127.0.0.1" })</code></li>
     *   <li><code>http:Listener httpListener = new(host = "127.0.0.1", port = 9090)</code></li>
     *   <li><code>http:Listener httpListener = check http:getDefaultListener()</code></li>
     * </ul>
     * <p>
     * Named arguments may appear in any order; the {@code port}/{@code listenOn} and {@code host}
     * arguments are resolved by name rather than by position.
     * <p>
     * For any unhandled or unexpected listener patterns, a default server instance is generated using
     * the provided base path and default host/port values along with a warning message.
     *
     * @param basePath   the absolute base path of the service (used as the path component of the server URL)
     * @param argListOpt the optional list of listener constructor arguments extracted from the syntax tree
     * @return a {@link Server} instance populated with the appropriate host, port, and URL variables
     */
    private Server generateServer(String basePath, Optional<ParenthesizedArgList> argListOpt) {
        ServerVariables serverVars = new ServerVariables();
        String port = null;
        String host = null;

        if (argListOpt.isPresent()) {
            SeparatedNodeList<FunctionArgumentNode> args = argListOpt.get().arguments();

            FunctionArgumentNode portArg = findPortArgument(args);
            if (portArg != null) {
                Optional<Server> resolvedServer = resolveListenerServer(basePath, getArgumentExpression(portArg));
                if (resolvedServer.isPresent()) {
                    return resolvedServer.get();
                }
                port = getValidPort(portArg);
            }

            host = findHost(args);
        }

        return buildServer(basePath, port, host, serverVars);
    }

    /**
     * Finds the argument that carries the port/listener value. Positional arguments must precede named
     * arguments in Ballerina, so the first positional argument (if any) is the port; otherwise the port
     * may be supplied as a named {@code port}/{@code listenOn} argument anywhere in the argument list.
     *
     * @param args the listener constructor arguments
     * @return the argument carrying the port value, or {@code null} if none is found
     */
    private static FunctionArgumentNode findPortArgument(SeparatedNodeList<FunctionArgumentNode> args) {
        for (FunctionArgumentNode arg : args) {
            if (arg instanceof PositionalArgumentNode) {
                return arg;
            }
            if (arg instanceof NamedArgumentNode namedArg
                    && (namedArg.argumentName().name().text().strip().equals(PORT)
                    || namedArg.argumentName().name().text().strip().equals(LISTEN_ON))) {
                return arg;
            }
        }
        return null;
    }

    /**
     * Finds the host value from the listener constructor arguments. The host may be supplied either as a
     * named {@code host} argument (an included {@code ListenerConfiguration} field) or as the {@code host}
     * field of a positional configuration mapping. A named {@code host} argument takes precedence.
     *
     * @param args the listener constructor arguments
     * @return the host value, or {@code null} if none is found
     */
    private String findHost(SeparatedNodeList<FunctionArgumentNode> args) {
        String host = null;
        for (FunctionArgumentNode arg : args) {
            if (arg instanceof NamedArgumentNode namedArg
                    && HOST_FIELD_NAME.equals(namedArg.argumentName().name().text().strip())) {
                return extractHost(namedArg);
            }
            if (arg instanceof PositionalArgumentNode posArg
                    && posArg.expression() instanceof MappingConstructorExpressionNode mapping) {
                host = extractHost(mapping);
            }
        }
        return host;
    }

    private static ExpressionNode getArgumentExpression(FunctionArgumentNode arg) {
        if (arg instanceof PositionalArgumentNode posArg) {
            return posArg.expression();
        } else if (arg instanceof NamedArgumentNode namedArg) {
            return namedArg.expression();
        }
        return null;
    }

    /**
     * Resolves a {@link Server} when the given listener argument expression references another listener
     * rather than directly specifying a port. This covers two cases:
     * <ul>
     *   <li>a reference to a module-level listener variable (e.g. {@code listenOn = httpListener})</li>
     *   <li>an inline listener expression (e.g. {@code listenOn = check new http:Listener(9091)})</li>
     * </ul>
     * In both cases the referenced listener's argument list is extracted and {@link #generateServer} is
     * applied recursively so the real port and host are used.
     *
     * @param basePath   the absolute base path of the service
     * @param expression the listener argument expression
     * @return the resolved server if the expression refers to another listener; otherwise empty
     */
    private Optional<Server> resolveListenerServer(String basePath, ExpressionNode expression) {
        Optional<Symbol> symbol = semanticModel.symbol(expression);
        if (symbol.isPresent() && symbol.get() instanceof VariableSymbol) {
            String varName = expression.toSourceCode().strip();
            if (endpoints.containsKey(varName)) {
                return Optional.of(generateServer(basePath,
                        extractListenerArgList(endpoints.get(varName).initializer())));
            }
        }
        Optional<ParenthesizedArgList> inlineArgList = extractListenerArgList(expression);
        if (inlineArgList.isPresent()) {
            return Optional.of(generateServer(basePath, inlineArgList));
        }
        return Optional.empty();
    }

    private String extractHost(NamedArgumentNode namedArg) {
        if (namedArg.expression() instanceof BasicLiteralNode bln) {
            return bln.toSourceCode().replaceAll("\"", "").trim();
        }
        return null;
    }

    private static String extractHost(MappingConstructorExpressionNode mapping) {
        for (MappingFieldNode field : mapping.fields()) {
            if (field instanceof SpecificFieldNode specific && HOST_FIELD_NAME.equals(specific.fieldName().toString())
                    && specific.valueExpr().isPresent()) {
                return specific.valueExpr().get().toString().replaceAll("\"", "");
            }
        }
        return null;
    }

    private String getValidPort(FunctionArgumentNode functionArgumentNode) {
        String text = functionArgumentNode.toString();
        if (functionArgumentNode instanceof NamedArgumentNode namedArgumentNode) {
            text = namedArgumentNode.expression().toSourceCode().trim();
        } else if (functionArgumentNode instanceof PositionalArgumentNode positionalArgumentNode) {
            text = positionalArgumentNode.expression().toSourceCode().trim();
        }
        if (text.matches(".*http:getDefaultListener.*$")) {
            return DEFAULT_HTTP_PORT;
        }
        if (text.matches("\\d+")) {
            return text;
        }
        addDiagnosticWarning(UNABLE_TO_OBTAIN_VALID_SERVER_PORT_FROM_EXPRESSION,
                functionArgumentNode.location(),
                functionArgumentNode.toSourceCode().strip(), DEFAULT_HTTP_PORT);
        return DEFAULT_HTTP_PORT;
    }

    private Server buildServer(String basePath, String port, String host, ServerVariables serverVars) {
        if (port == null) {
            addDiagnosticWarning(UNABLE_TO_OBTAIN_VALID_SERVER_PORT, new NullLocation(), DEFAULT_HTTP_PORT);
            port = DEFAULT_HTTP_PORT;
        }
        ServerVariable serverVar = new ServerVariable();
        serverVar._default(host != null ? host : (port.equals(PORT_443) ? HTTPS_LOCALHOST : HTTP_LOCALHOST));

        ServerVariable portVar = new ServerVariable();
        portVar._default(port);

        serverVars.addServerVariable(SERVER, serverVar);
        serverVars.addServerVariable(PORT, portVar);

        Server server = new Server();
        server.setVariables(serverVars);
        server.setUrl(String.format("{server}:{port}%s", basePath));
        return server;
    }

    private void addDiagnosticWarning(CompilationDiagnostic compilationDiagnostic, Location location, Object... args) {
        Diagnostic diagnostic = getDiagnostic(compilationDiagnostic, location, args);
        this.diagnostics.add(diagnostic);
    }

    private Server getDefaultServerWithBasePath(String basePath) {
        return buildServer(basePath, null, null, new ServerVariables());
    }

    private String getServiceBasePath() {
        StringBuilder path = new StringBuilder();
        for (Node node : this.service.absoluteResourcePath()) {
            path.append(MapperCommonUtils.unescapeIdentifier(node.toString()));
        }
        return path.toString().trim();
    }

    public List<Diagnostic> getDiagnostics() {
        return Collections.unmodifiableList(this.diagnostics);
    }
}
