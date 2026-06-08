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
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.SymbolKind;
import io.ballerina.compiler.api.symbols.TypeDescKind;
import io.ballerina.compiler.api.symbols.TypeReferenceTypeSymbol;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.api.symbols.UnionTypeSymbol;
import io.ballerina.compiler.syntax.tree.BasicLiteralNode;
import io.ballerina.compiler.syntax.tree.ClassDefinitionNode;
import io.ballerina.compiler.syntax.tree.ExplicitNewExpressionNode;
import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.FieldAccessExpressionNode;
import io.ballerina.compiler.syntax.tree.FunctionArgumentNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.ImplicitNewExpressionNode;
import io.ballerina.compiler.syntax.tree.ListConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.MappingConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.NamedArgumentNode;
import io.ballerina.compiler.syntax.tree.NewExpressionNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.NodeVisitor;
import io.ballerina.compiler.syntax.tree.ParenthesizedArgList;
import io.ballerina.compiler.syntax.tree.QualifiedNameReferenceNode;
import io.ballerina.compiler.syntax.tree.SeparatedNodeList;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.compiler.syntax.tree.TypeReferenceNode;
import io.ballerina.projects.DocumentId;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * Analyzes custom agent definitions (classes implementing `ai:AgentType`) and gathers the names of the tools passed to
 * the `ai:Agent` constructed within the class's `init` method. The gathered metadata is later attached to the class as
 * an `@ai:AgentMetadata` annotation by the {@link AiSourceModifier}, so that consumers of a shared agent definition can
 * discover the tools without access to the implementation.
 */
class CustomAgentAnalysisTask implements AnalysisTask<SyntaxNodeAnalysisContext> {

    private static final String AGENT_CLASS_NAME = "Agent";
    private static final String FIXED_RETURN_AGENT_TYPE_NAME = "FixedReturnAgentType";
    private static final String INFERRED_RETURN_AGENT_TYPE_NAME = "InferredReturnAgentType";
    private static final String INIT_METHOD_NAME = "init";
    private static final String TOOLS_ARG_NAME = "tools";
    private static final String TOOL_CONFIG_NAME_FIELD = "name";
    private static final String SELF_KEYWORD = "self";

    private final Map<DocumentId, ModifierContext> modifierContextMap;

    CustomAgentAnalysisTask(Map<DocumentId, ModifierContext> modifierContextMap) {
        this.modifierContextMap = modifierContextMap;
    }

    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        if (!(context.node() instanceof ClassDefinitionNode classDefinitionNode)) {
            return;
        }
        SemanticModel semanticModel = context.semanticModel();
        Optional<String> aiModulePrefix = getAgentTypeInclusionPrefix(semanticModel, classDefinitionNode);
        if (aiModulePrefix.isEmpty()) {
            return;
        }
        Optional<FunctionDefinitionNode> initMethod = getInitMethod(classDefinitionNode);
        if (initMethod.isEmpty()) {
            return;
        }
        List<String> toolNames = getToolNames(semanticModel, initMethod.get());
        this.modifierContextMap.computeIfAbsent(context.documentId(), document -> new ModifierContext())
                .add(classDefinitionNode, new AgentMetadataConfig(aiModulePrefix.get(), toolNames));
    }

    /**
     * Returns the `ballerina/ai` module prefix used by the class's `*ai:FixedReturnAgentType` or
     * `*ai:InferredReturnAgentType` type inclusion, or empty if the class is not a custom agent definition.
     */
    private Optional<String> getAgentTypeInclusionPrefix(SemanticModel semanticModel,
                                                         ClassDefinitionNode classDefinitionNode) {
        for (Node member : classDefinitionNode.members()) {
            if (member.kind() != SyntaxKind.TYPE_REFERENCE) {
                continue;
            }
            Node typeName = ((TypeReferenceNode) member).typeName();
            if (typeName.kind() != SyntaxKind.QUALIFIED_NAME_REFERENCE) {
                continue;
            }
            QualifiedNameReferenceNode qualifiedTypeName = (QualifiedNameReferenceNode) typeName;
            String identifier = qualifiedTypeName.identifier().text();
            if (!FIXED_RETURN_AGENT_TYPE_NAME.equals(identifier)
                    && !INFERRED_RETURN_AGENT_TYPE_NAME.equals(identifier)) {
                continue;
            }
            Optional<Symbol> typeSymbol = semanticModel.symbol(qualifiedTypeName);
            if (typeSymbol.isPresent() && Utils.isAgentModuleSymbol(typeSymbol.get())) {
                return Optional.of(qualifiedTypeName.modulePrefix().text());
            }
        }
        return Optional.empty();
    }

    private Optional<FunctionDefinitionNode> getInitMethod(ClassDefinitionNode classDefinitionNode) {
        for (Node member : classDefinitionNode.members()) {
            if (member.kind() == SyntaxKind.OBJECT_METHOD_DEFINITION
                    && member instanceof FunctionDefinitionNode functionDefinitionNode
                    && INIT_METHOD_NAME.equals(functionDefinitionNode.functionName().text())) {
                return Optional.of(functionDefinitionNode);
            }
        }
        return Optional.empty();
    }

    /**
     * Collects the statically identifiable tool names from the `tools` argument of every `ai:Agent` constructed within
     * the given `init` method.
     */
    private List<String> getToolNames(SemanticModel semanticModel, FunctionDefinitionNode initMethod) {
        AgentNewExpressionVisitor visitor = new AgentNewExpressionVisitor(semanticModel);
        initMethod.accept(visitor);
        Set<String> toolNames = new LinkedHashSet<>();
        for (NewExpressionNode newExpression : visitor.getAgentNewExpressions()) {
            Optional<ListConstructorExpressionNode> toolsList = getToolsArgument(newExpression);
            if (toolsList.isEmpty()) {
                continue;
            }
            for (Node element : toolsList.get().expressions()) {
                // Entries that cannot be statically resolved to a tool name (e.g., toolkit instances or
                // variable references to tool lists) are skipped.
                getToolName(semanticModel, element).ifPresent(toolNames::add);
            }
        }
        return new ArrayList<>(toolNames);
    }

    private Optional<ListConstructorExpressionNode> getToolsArgument(NewExpressionNode newExpressionNode) {
        Optional<SeparatedNodeList<FunctionArgumentNode>> arguments = getArguments(newExpressionNode);
        if (arguments.isEmpty()) {
            return Optional.empty();
        }
        // `Agent.init` accepts an included record parameter (`*AgentConfiguration`), so the tools are
        // always passed as a named argument: `tools = [...]`.
        for (FunctionArgumentNode argument : arguments.get()) {
            if (argument.kind() != SyntaxKind.NAMED_ARG) {
                continue;
            }
            NamedArgumentNode namedArgument = (NamedArgumentNode) argument;
            if (!TOOLS_ARG_NAME.equals(namedArgument.argumentName().name().text())) {
                continue;
            }
            ExpressionNode expression = namedArgument.expression();
            if (expression.kind() == SyntaxKind.LIST_CONSTRUCTOR) {
                return Optional.of((ListConstructorExpressionNode) expression);
            }
        }
        return Optional.empty();
    }

    private Optional<SeparatedNodeList<FunctionArgumentNode>> getArguments(NewExpressionNode newExpressionNode) {
        if (newExpressionNode instanceof ExplicitNewExpressionNode explicitNewExpressionNode) {
            return Optional.of(explicitNewExpressionNode.parenthesizedArgList().arguments());
        }
        if (newExpressionNode instanceof ImplicitNewExpressionNode implicitNewExpressionNode) {
            return implicitNewExpressionNode.parenthesizedArgList().map(ParenthesizedArgList::arguments);
        }
        return Optional.empty();
    }

    private Optional<String> getToolName(SemanticModel semanticModel, Node element) {
        return switch (element.kind()) {
            // A function pointer (`searchDoc`, `mod:searchDoc`) or an object method reference
            // (`self.searchDoc`); the runtime tool name defaults to the function/method name.
            case SIMPLE_NAME_REFERENCE, QUALIFIED_NAME_REFERENCE, FIELD_ACCESS ->
                    getFunctionOrMethodName(semanticModel, element);
            // An inline `ai:ToolConfig` mapping constructor with an explicit `name` field.
            case MAPPING_CONSTRUCTOR -> getToolConfigName((MappingConstructorExpressionNode) element);
            default -> Optional.empty();
        };
    }

    private Optional<String> getFunctionOrMethodName(SemanticModel semanticModel, Node element) {
        if (element.kind() == SyntaxKind.FIELD_ACCESS) {
            // A bound-method reference (`self.createSchedule`): the symbol API does not resolve the
            // method symbol for these, so rely on the syntax.
            FieldAccessExpressionNode fieldAccess = (FieldAccessExpressionNode) element;
            if (fieldAccess.expression().kind() == SyntaxKind.SIMPLE_NAME_REFERENCE
                    && SELF_KEYWORD.equals(fieldAccess.expression().toSourceCode().trim())) {
                return Optional.of(fieldAccess.fieldName().toSourceCode().trim());
            }
            return Optional.empty();
        }
        return semanticModel.symbol(element)
                .filter(value -> value.kind() == SymbolKind.FUNCTION || value.kind() == SymbolKind.METHOD)
                .flatMap(Symbol::getName);
    }

    private Optional<String> getToolConfigName(MappingConstructorExpressionNode mappingConstructor) {
        for (MappingFieldNode field : mappingConstructor.fields()) {
            if (field.kind() != SyntaxKind.SPECIFIC_FIELD) {
                continue;
            }
            SpecificFieldNode specificField = (SpecificFieldNode) field;
            String fieldName = specificField.fieldName().toSourceCode().trim();
            if (!TOOL_CONFIG_NAME_FIELD.equals(fieldName) && !"\"name\"".equals(fieldName)) {
                continue;
            }
            Optional<ExpressionNode> valueExpression = specificField.valueExpr();
            if (valueExpression.isPresent() && valueExpression.get().kind() == SyntaxKind.STRING_LITERAL) {
                String literal = ((BasicLiteralNode) valueExpression.get()).literalToken().text();
                return Optional.of(literal.substring(1, literal.length() - 1));
            }
        }
        return Optional.empty();
    }

    /**
     * Collects every `new` expression within a function body whose static type is (or includes) the `ai:Agent` class —
     * covering `self.agent = check new (...)`, explicit `new ai:Agent(...)`, and agents assigned to locals.
     */
    private static class AgentNewExpressionVisitor extends NodeVisitor {

        private final SemanticModel semanticModel;
        private final List<NewExpressionNode> agentNewExpressions = new ArrayList<>();

        AgentNewExpressionVisitor(SemanticModel semanticModel) {
            this.semanticModel = semanticModel;
        }

        List<NewExpressionNode> getAgentNewExpressions() {
            return agentNewExpressions;
        }

        @Override
        public void visit(ImplicitNewExpressionNode implicitNewExpressionNode) {
            addIfAgentNewExpression(implicitNewExpressionNode);
            super.visit(implicitNewExpressionNode);
        }

        @Override
        public void visit(ExplicitNewExpressionNode explicitNewExpressionNode) {
            addIfAgentNewExpression(explicitNewExpressionNode);
            super.visit(explicitNewExpressionNode);
        }

        private void addIfAgentNewExpression(NewExpressionNode newExpressionNode) {
            // A `new` expression types as `Agent|ai:Error` when the `init` method can fail.
            Optional<TypeSymbol> type = semanticModel.typeOf(newExpressionNode);
            if (type.isPresent() && containsAiAgentType(type.get())) {
                agentNewExpressions.add(newExpressionNode);
            }
        }

        private boolean containsAiAgentType(TypeSymbol typeSymbol) {
            if (typeSymbol.typeKind() == TypeDescKind.UNION) {
                return ((UnionTypeSymbol) typeSymbol).memberTypeDescriptors().stream()
                        .anyMatch(this::containsAiAgentType);
            }
            if (typeSymbol.typeKind() == TypeDescKind.TYPE_REFERENCE) {
                Symbol definition = ((TypeReferenceTypeSymbol) typeSymbol).definition();
                return AGENT_CLASS_NAME.equals(definition.getName().orElse(""))
                        && Utils.isAgentModuleSymbol(definition);
            }
            return AGENT_CLASS_NAME.equals(typeSymbol.getName().orElse(""))
                    && Utils.isAgentModuleSymbol(typeSymbol);
        }
    }
}
