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
import io.ballerina.compiler.api.symbols.AnnotationAttachmentSymbol;
import io.ballerina.compiler.api.symbols.AnnotationSymbol;
import io.ballerina.compiler.api.symbols.ClassSymbol;
import io.ballerina.compiler.api.symbols.ConstantSymbol;
import io.ballerina.compiler.api.symbols.FunctionSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.SymbolKind;
import io.ballerina.compiler.api.symbols.TypeDefinitionSymbol;
import io.ballerina.compiler.api.symbols.TypeReferenceTypeSymbol;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.api.symbols.UnionTypeSymbol;
import io.ballerina.compiler.api.values.ConstantValue;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.BasicLiteralNode;
import io.ballerina.compiler.syntax.tree.CheckExpressionNode;
import io.ballerina.compiler.syntax.tree.ClassDefinitionNode;
import io.ballerina.compiler.syntax.tree.DefaultableParameterNode;
import io.ballerina.compiler.syntax.tree.ExplicitNewExpressionNode;
import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.FieldAccessExpressionNode;
import io.ballerina.compiler.syntax.tree.FunctionArgumentNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.ImplicitNewExpressionNode;
import io.ballerina.compiler.syntax.tree.InterpolationNode;
import io.ballerina.compiler.syntax.tree.ListConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.MappingConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.NameReferenceNode;
import io.ballerina.compiler.syntax.tree.NamedArgumentNode;
import io.ballerina.compiler.syntax.tree.NewExpressionNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.NodeVisitor;
import io.ballerina.compiler.syntax.tree.ParameterNode;
import io.ballerina.compiler.syntax.tree.ParenthesizedArgList;
import io.ballerina.compiler.syntax.tree.QualifiedNameReferenceNode;
import io.ballerina.compiler.syntax.tree.RequiredParameterNode;
import io.ballerina.compiler.syntax.tree.SeparatedNodeList;
import io.ballerina.compiler.syntax.tree.SimpleNameReferenceNode;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.compiler.syntax.tree.TemplateExpressionNode;
import io.ballerina.compiler.syntax.tree.TypeReferenceNode;
import io.ballerina.projects.DocumentId;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Analyzes custom agent definitions (classes implementing `ai:AgentType`) and gathers metadata about the tools passed
 * to the `ai:Agent` constructed within the class's `init` method. The gathered metadata is later recorded in the
 * `agentMetadata` field of the class's `@display` annotation by the {@link AiSourceModifier}, so consumers of a shared
 * agent definition can discover its tools without access to the implementation.
 *
 * <p>For each entry in the agent's `tools` list, the following is collected (entries that cannot be resolved
 * statically — e.g., a `ToolConfig` variable or `tools = someList` — are skipped):
 * <ul>
 *     <li>A function/method tool: its name and, if present, its `@display` label and icon.</li>
 *     <li>An MCP toolkit (a subtype of `ai:McpBaseToolKit`): its variable name (or type name if constructed inline),
 *     marked as {@link ToolKind#MCP_TOOLKIT}. Individual MCP tools are resolved from the server at runtime and so
 *     cannot be listed.</li>
 *     <li>Any other toolkit: its variable/type name, marked as {@link ToolKind#TOOLKIT}.</li>
 * </ul>
 *
 * <p>Additionally, when the agent's `model` or `memory` argument is a direct reference to an `init` parameter, the
 * parameter's name is recorded — telling consumers which constructor inputs supply the model provider and the memory.
 */
class CustomAgentAnalysisTask implements AnalysisTask<SyntaxNodeAnalysisContext> {

    private static final String AGENT_CLASS_NAME = "Agent";
    private static final String FIXED_RETURN_AGENT_TYPE_NAME = "FixedReturnAgentType";
    private static final String INFERRED_RETURN_AGENT_TYPE_NAME = "InferredReturnAgentType";
    private static final String MCP_BASE_TOOLKIT_NAME = "McpBaseToolKit";
    private static final String BASE_TOOLKIT_NAME = "BaseToolKit";
    private static final String INIT_METHOD_NAME = "init";
    private static final String TOOLS_ARG_NAME = "tools";
    private static final String MODEL_ARG_NAME = "model";
    private static final String MEMORY_ARG_NAME = "memory";
    private static final String SYSTEM_PROMPT_ARG_NAME = "systemPrompt";
    private static final String SYSTEM_PROMPT_ROLE_FIELD = "role";
    private static final String SYSTEM_PROMPT_INSTRUCTIONS_FIELD = "instructions";
    private static final String TOOL_CONFIG_NAME_FIELD = "name";
    private static final String DISPLAY_ANNOTATION_NAME = "display";
    private static final String DISPLAY_LABEL_FIELD = "label";
    private static final String DISPLAY_ICON_FIELD = "iconPath";
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
        AnalysisContext analysisContext = new AnalysisContext(semanticModel,
                getAiType(semanticModel, MCP_BASE_TOOLKIT_NAME), getAiType(semanticModel, BASE_TOOLKIT_NAME),
                getClassMethods(classDefinitionNode));
        Optional<FunctionDefinitionNode> initMethod = getInitMethod(classDefinitionNode);
        List<NewExpressionNode> agentNewExpressions = initMethod
                .map(method -> getAgentNewExpressions(semanticModel, method))
                .orElse(List.of());
        List<ToolMetadata> tools = getTools(analysisContext, agentNewExpressions);
        List<String> initParameterNames = initMethod.map(this::getParameterNames).orElse(List.of());
        String modelProviderParamName =
                getInjectedParameterName(semanticModel, agentNewExpressions, MODEL_ARG_NAME, initParameterNames);
        String memoryParamName =
                getInjectedParameterName(semanticModel, agentNewExpressions, MEMORY_ARG_NAME, initParameterNames);
        SystemPromptMetadata systemPrompt = getSystemPrompt(semanticModel, agentNewExpressions);
        this.modifierContextMap.computeIfAbsent(context.documentId(), document -> new ModifierContext())
                .add(classDefinitionNode, new AgentMetadataConfig(aiModulePrefix.get(), tools, systemPrompt,
                        modelProviderParamName, memoryParamName));
    }

    /**
     * Returns the `ballerina/ai` module prefix used by the class's `*ai:FixedReturnAgentType` or
     * `*ai:InferredReturnAgentType` type inclusion, or empty if the class is not a custom agent definition.
     */
    private Optional<String> getAgentTypeInclusionPrefix(SemanticModel semanticModel,
                                                         ClassDefinitionNode classDefinitionNode) {
        for (Node member : classDefinitionNode.members()) {
            if (!(member instanceof TypeReferenceNode typeReference)
                    || !(typeReference.typeName() instanceof QualifiedNameReferenceNode qualifiedTypeName)) {
                continue;
            }
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
            if (member instanceof FunctionDefinitionNode functionDefinitionNode
                    && INIT_METHOD_NAME.equals(functionDefinitionNode.functionName().text())) {
                return Optional.of(functionDefinitionNode);
            }
        }
        return Optional.empty();
    }

    private Map<String, FunctionDefinitionNode> getClassMethods(ClassDefinitionNode classDefinitionNode) {
        Map<String, FunctionDefinitionNode> methods = new HashMap<>();
        for (Node member : classDefinitionNode.members()) {
            if (member instanceof FunctionDefinitionNode functionDefinitionNode) {
                methods.put(functionDefinitionNode.functionName().text(), functionDefinitionNode);
            }
        }
        return methods;
    }

    private List<NewExpressionNode> getAgentNewExpressions(SemanticModel semanticModel,
                                                           FunctionDefinitionNode initMethod) {
        AgentNewExpressionVisitor visitor = new AgentNewExpressionVisitor(semanticModel);
        initMethod.accept(visitor);
        return visitor.getAgentNewExpressions();
    }

    /**
     * Collects the statically identifiable tools from the `tools` argument of every `ai:Agent` constructed within the
     * `init` method.
     */
    private List<ToolMetadata> getTools(AnalysisContext analysisContext,
                                        List<NewExpressionNode> agentNewExpressions) {
        Map<String, ToolMetadata> tools = new LinkedHashMap<>();
        for (NewExpressionNode newExpression : agentNewExpressions) {
            Optional<ListConstructorExpressionNode> toolsList = getToolsArgument(newExpression);
            if (toolsList.isEmpty()) {
                continue;
            }
            for (Node element : toolsList.get().expressions()) {
                getToolMetadata(analysisContext, element)
                        .ifPresent(tool -> tools.putIfAbsent(tool.name(), tool));
            }
        }
        return new ArrayList<>(tools.values());
    }

    private List<String> getParameterNames(FunctionDefinitionNode method) {
        List<String> names = new ArrayList<>();
        for (ParameterNode parameter : method.functionSignature().parameters()) {
            switch (parameter) {
                case RequiredParameterNode requiredParameter ->
                        requiredParameter.paramName().ifPresent(name -> names.add(name.text()));
                case DefaultableParameterNode defaultableParameter ->
                        defaultableParameter.paramName().ifPresent(name -> names.add(name.text()));
                default -> {
                }
            }
        }
        return names;
    }

    /**
     * Returns the name of the `init` parameter passed as the given named argument (e.g., `model` or `memory`) of an
     * `ai:Agent` constructed within `init`, or {@code null} when the argument is absent or its value is anything other
     * than a direct reference to an `init` parameter.
     */
    private String getInjectedParameterName(SemanticModel semanticModel,
                                            List<NewExpressionNode> agentNewExpressions,
                                            String argumentName, List<String> initParameterNames) {
        for (NewExpressionNode newExpression : agentNewExpressions) {
            Optional<ExpressionNode> argumentValue = getNamedArgumentValue(newExpression, argumentName);
            if (argumentValue.isEmpty()) {
                continue;
            }
            if (!(unwrapCheck(argumentValue.get()) instanceof SimpleNameReferenceNode reference)) {
                continue;
            }
            String referencedName = reference.name().text();
            if (initParameterNames.contains(referencedName) && isParameterReference(semanticModel, reference)) {
                return referencedName;
            }
        }
        return null;
    }

    private boolean isParameterReference(SemanticModel semanticModel, Node node) {
        return semanticModel.symbol(node)
                .map(symbol -> symbol.kind() == SymbolKind.PARAMETER)
                .orElse(false);
    }

    private Optional<ToolMetadata> getToolMetadata(AnalysisContext analysisContext, Node element) {
        return switch (unwrapCheck(element)) {
            case NameReferenceNode reference -> getReferenceToolMetadata(analysisContext, reference);
            case FieldAccessExpressionNode fieldAccess -> getReferenceToolMetadata(analysisContext, fieldAccess);
            // An inline `ai:ToolConfig` mapping constructor with an explicit `name` field.
            case MappingConstructorExpressionNode mapping -> getStringLiteralField(mapping, TOOL_CONFIG_NAME_FIELD)
                    .map(name -> new ToolMetadata(name, ToolKind.FUNCTION_TOOL, null, null));
            // A toolkit constructed inline (`check new ai:McpToolKit(...)`); use its type name.
            case NewExpressionNode newExpression -> getInlineToolkitMetadata(analysisContext, newExpression);
            default -> Optional.empty();
        };
    }

    /**
     * Resolves a tool referenced by name: a function/method reference becomes a {@link ToolKind#FUNCTION_TOOL} tool
     * (with its `@display` metadata, if any), while a variable/field whose type is a toolkit becomes a toolkit entry
     * named after the reference. Anything else (e.g., a `ToolConfig` variable) is skipped.
     */
    private Optional<ToolMetadata> getReferenceToolMetadata(AnalysisContext analysisContext, Node element) {
        SemanticModel semanticModel = analysisContext.semanticModel();
        Optional<Symbol> symbol = semanticModel.symbol(element);
        if (symbol.isPresent() && isFunctionOrMethod(symbol.get())) {
            DisplayInfo display = readDisplay((FunctionSymbol) symbol.get());
            return symbol.get().getName()
                    .map(name -> new ToolMetadata(name, ToolKind.FUNCTION_TOOL, display.label(), display.icon()));
        }
        Optional<ToolKind> toolkitKind =
                semanticModel.typeOf(element).flatMap(type -> classifyToolkit(analysisContext, type));
        if (toolkitKind.isPresent()) {
            return getReferenceName(element)
                    .map(name -> new ToolMetadata(name, toolkitKind.get(), null, null));
        }

        if (element instanceof FieldAccessExpressionNode fieldAccess
                && fieldAccess.expression() instanceof SimpleNameReferenceNode selfReference
                && SELF_KEYWORD.equals(selfReference.name().text())) {
            String name = fieldAccess.fieldName().toSourceCode().trim();
            DisplayInfo display = readDisplay(analysisContext.classMethods().get(name));
            return Optional.of(new ToolMetadata(name, ToolKind.FUNCTION_TOOL, display.label(), display.icon()));
        }
        return Optional.empty();
    }

    private Optional<ToolMetadata> getInlineToolkitMetadata(AnalysisContext analysisContext, ExpressionNode newExpr) {
        Optional<TypeSymbol> type = analysisContext.semanticModel().typeOf(newExpr);
        if (type.isEmpty()) {
            return Optional.empty();
        }
        Optional<ToolKind> toolkitKind = classifyToolkit(analysisContext, type.get());
        return toolkitKind.flatMap(kind -> toolkitTypeName(analysisContext, type.get())
                .map(name -> new ToolMetadata(name, kind, null, null)));
    }

    private boolean isFunctionOrMethod(Symbol symbol) {
        return symbol.kind() == SymbolKind.FUNCTION || symbol.kind() == SymbolKind.METHOD;
    }

    private Optional<String> getReferenceName(Node element) {
        return switch (element) {
            case SimpleNameReferenceNode refNode -> Optional.of(refNode.name().text());
            case QualifiedNameReferenceNode refNode -> Optional.of(refNode.identifier().text());
            case FieldAccessExpressionNode refNode -> Optional.of(refNode.fieldName().toSourceCode().trim());
            default -> Optional.empty();
        };
    }

    /**
     * Classifies a type as an MCP toolkit, another toolkit, or neither. Unions (e.g., `McpToolKit|ai:Error` for an
     * inline `check new`) are flattened and any toolkit member is matched.
     */
    private Optional<ToolKind> classifyToolkit(AnalysisContext analysisContext, TypeSymbol typeSymbol) {
        List<TypeSymbol> members = flattenUnion(typeSymbol);
        if (members.stream().anyMatch(member -> subtypeOf(member, analysisContext.mcpToolKitType()))) {
            return Optional.of(ToolKind.MCP_TOOLKIT);
        }
        if (members.stream().anyMatch(member -> subtypeOf(member, analysisContext.baseToolKitType()))) {
            return Optional.of(ToolKind.TOOLKIT);
        }
        return Optional.empty();
    }

    private Optional<String> toolkitTypeName(AnalysisContext analysisContext, TypeSymbol typeSymbol) {
        return flattenUnion(typeSymbol).stream()
                .filter(member -> subtypeOf(member, analysisContext.baseToolKitType()))
                .findFirst()
                .flatMap(Symbol::getName);
    }

    private List<TypeSymbol> flattenUnion(TypeSymbol typeSymbol) {
        if (typeSymbol instanceof UnionTypeSymbol unionTypeSymbol) {
            List<TypeSymbol> members = new ArrayList<>();
            for (TypeSymbol member : unionTypeSymbol.memberTypeDescriptors()) {
                members.addAll(flattenUnion(member));
            }
            return members;
        }
        return List.of(typeSymbol);
    }

    private boolean subtypeOf(TypeSymbol typeSymbol, TypeSymbol target) {
        return target != null && typeSymbol.subtypeOf(target);
    }

    private TypeSymbol getAiType(SemanticModel semanticModel, String typeName) {
        Optional<Symbol> symbol = semanticModel.types()
                .getTypeByName(Utils.BALLERINA_ORG, Utils.AI_PACKAGE_NAME, Utils.AI_PACKAGE_MAJOR_VERSION, typeName);
        return symbol.map(value -> switch (value) {
            case ClassSymbol classSymbol -> classSymbol;
            case TypeDefinitionSymbol typeDefinitionSymbol -> typeDefinitionSymbol.typeDescriptor();
            default -> null;
        }).orElse(null);
    }

    /**
     * Reads the `@display` annotation of a resolved function/method symbol. Since `@display` is a `const` annotation,
     * its value is available via the symbol API for both same-module and imported tools.
     */
    private DisplayInfo readDisplay(FunctionSymbol functionSymbol) {
        for (AnnotationAttachmentSymbol attachment : functionSymbol.annotAttachments()) {
            if (!isDisplayAnnotation(attachment.typeDescriptor()) || !attachment.isConstAnnotation()) {
                continue;
            }
            Optional<ConstantValue> value = attachment.attachmentValue();
            if (value.isPresent() && value.get().value() instanceof Map<?, ?> fields) {
                return new DisplayInfo(constStringValue(fields.get(DISPLAY_LABEL_FIELD)),
                        constStringValue(fields.get(DISPLAY_ICON_FIELD)));
            }
        }
        return DisplayInfo.EMPTY;
    }

    /**
     * Reads the `@display` annotation from a method node syntactically. Used for `self.method` tool references, which
     * do not resolve to a symbol.
     */
    private DisplayInfo readDisplay(FunctionDefinitionNode methodNode) {
        if (methodNode == null || methodNode.metadata().isEmpty()) {
            return DisplayInfo.EMPTY;
        }
        for (AnnotationNode annotation : methodNode.metadata().get().annotations()) {
            if (annotation.annotReference() instanceof SimpleNameReferenceNode annotReference
                    && DISPLAY_ANNOTATION_NAME.equals(annotReference.name().text())
                    && annotation.annotValue().isPresent()) {
                MappingConstructorExpressionNode value = annotation.annotValue().get();
                return new DisplayInfo(getStringLiteralField(value, DISPLAY_LABEL_FIELD).orElse(null),
                        getStringLiteralField(value, DISPLAY_ICON_FIELD).orElse(null));
            }
        }
        return DisplayInfo.EMPTY;
    }

    private boolean isDisplayAnnotation(AnnotationSymbol annotationSymbol) {
        return DISPLAY_ANNOTATION_NAME.equals(annotationSymbol.getName().orElse(""))
                && annotationSymbol.getModule()
                .map(module -> Utils.BALLERINA_ORG.equals(module.id().orgName()))
                .orElse(false);
    }

    private String constStringValue(Object value) {
        if (value instanceof ConstantValue constantValue) {
            return constStringValue(constantValue.value());
        }
        return value instanceof String stringValue ? stringValue : null;
    }

    private Optional<String> getStringLiteralField(MappingConstructorExpressionNode mappingConstructor,
                                                   String fieldName) {
        return getMappingFieldValue(mappingConstructor, fieldName)
                .filter(value -> value.kind() == SyntaxKind.STRING_LITERAL)
                .map(value -> {
                    String literal = ((BasicLiteralNode) value).literalToken().text();
                    return literal.substring(1, literal.length() - 1);
                });
    }

    private Optional<ExpressionNode> getMappingFieldValue(MappingConstructorExpressionNode mappingConstructor,
                                                          String fieldName) {
        for (MappingFieldNode field : mappingConstructor.fields()) {
            if (!(field instanceof SpecificFieldNode specificField)) {
                continue;
            }
            String name = specificField.fieldName().toSourceCode().trim();
            if (fieldName.equals(name) || ("\"" + fieldName + "\"").equals(name)) {
                return specificField.valueExpr();
            }
        }
        return Optional.empty();
    }

    /**
     * Resolves the system prompt of an `ai:Agent` constructed within `init`. The prompt is resolved only when it is an
     * inline mapping whose `role` and `instructions` are both statically resolvable string values; anything else (e.g.,
     * a variable reference or a template with interpolations) yields {@code null}.
     */
    private SystemPromptMetadata getSystemPrompt(SemanticModel semanticModel,
                                                 List<NewExpressionNode> agentNewExpressions) {
        for (NewExpressionNode newExpression : agentNewExpressions) {
            Optional<ExpressionNode> argumentValue = getNamedArgumentValue(newExpression, SYSTEM_PROMPT_ARG_NAME);
            if (argumentValue.isEmpty()) {
                continue;
            }
            if (!(unwrapCheck(argumentValue.get()) instanceof MappingConstructorExpressionNode mapping)) {
                continue;
            }
            String role = getMappingFieldValue(mapping, SYSTEM_PROMPT_ROLE_FIELD)
                    .map(value -> getStaticStringValue(semanticModel, value)).orElse(null);
            String instructions = getMappingFieldValue(mapping, SYSTEM_PROMPT_INSTRUCTIONS_FIELD)
                    .map(value -> getStaticStringValue(semanticModel, value)).orElse(null);
            if (role != null && instructions != null) {
                return new SystemPromptMetadata(role, instructions);
            }
        }
        return null;
    }

    /**
     * Resolves an expression to a compile-time string value: a string literal, a string template without
     * interpolations, or a reference to a string constant. Returns {@code null} for anything else.
     */
    private String getStaticStringValue(SemanticModel semanticModel, ExpressionNode expression) {
        if (expression instanceof BasicLiteralNode literal && literal.kind() == SyntaxKind.STRING_LITERAL) {
            String text = literal.literalToken().text();
            return text.substring(1, text.length() - 1);
        }
        if (expression instanceof TemplateExpressionNode template
                && template.kind() == SyntaxKind.STRING_TEMPLATE_EXPRESSION) {
            StringBuilder text = new StringBuilder();
            for (Node member : template.content()) {
                if (member instanceof InterpolationNode) {
                    return null;
                }
                text.append(member.toSourceCode());
            }
            return text.toString();
        }
        if (expression instanceof NameReferenceNode) {
            return semanticModel.symbol(expression)
                    .filter(symbol -> symbol.kind() == SymbolKind.CONSTANT)
                    .map(symbol -> constStringValue(((ConstantSymbol) symbol).constValue()))
                    .orElse(null);
        }
        return null;
    }

    private Node unwrapCheck(Node element) {
        if (element instanceof CheckExpressionNode checkExpression) {
            return unwrapCheck(checkExpression.expression());
        }
        return element;
    }

    private Optional<ListConstructorExpressionNode> getToolsArgument(NewExpressionNode newExpressionNode) {
        return getNamedArgumentValue(newExpressionNode, TOOLS_ARG_NAME)
                .filter(ListConstructorExpressionNode.class::isInstance)
                .map(ListConstructorExpressionNode.class::cast);
    }

    /**
     * Returns the value of the given named argument of a `new` expression. `Agent.init` accepts an included record
     * parameter (`*AgentConfiguration`), so its config values are always passed as named arguments.
     */
    private Optional<ExpressionNode> getNamedArgumentValue(NewExpressionNode newExpressionNode, String argumentName) {
        Optional<SeparatedNodeList<FunctionArgumentNode>> arguments = getArguments(newExpressionNode);
        if (arguments.isEmpty()) {
            return Optional.empty();
        }
        for (FunctionArgumentNode argument : arguments.get()) {
            if (argument instanceof NamedArgumentNode namedArgument
                    && argumentName.equals(namedArgument.argumentName().name().text())) {
                return Optional.of(namedArgument.expression());
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
            if (typeSymbol instanceof UnionTypeSymbol unionTypeSymbol) {
                return unionTypeSymbol.memberTypeDescriptors().stream()
                        .anyMatch(this::containsAiAgentType);
            }
            if (typeSymbol instanceof TypeReferenceTypeSymbol typeReference) {
                Symbol definition = typeReference.definition();
                return AGENT_CLASS_NAME.equals(definition.getName().orElse(""))
                        && Utils.isAgentModuleSymbol(definition);
            }
            return AGENT_CLASS_NAME.equals(typeSymbol.getName().orElse(""))
                    && Utils.isAgentModuleSymbol(typeSymbol);
        }
    }

    // Per-class analysis state: the semantic model, the resolved toolkit base types used to classify tool entries, and
    // the class's methods (used to read `@display` from `self.method` tool references).
    private record AnalysisContext(SemanticModel semanticModel, TypeSymbol mcpToolKitType, TypeSymbol baseToolKitType,
                                   Map<String, FunctionDefinitionNode> classMethods) {
    }

    // The `@display` label and icon of a tool; either field may be null.
    private record DisplayInfo(String label, String icon) {

        private static final DisplayInfo EMPTY = new DisplayInfo(null, null);
    }
}
