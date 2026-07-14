// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ai.observe;

import ballerina/cache;
import ballerina/jballerina.java;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;

const INFER_TOOL_COUNT = "INFER_TOOL_COUNT";
const DEFAULT_MINIMUM_MAX_ITERATIONS = 10;

# Represents the system prompt given to the agent.
@display {label: "System Prompt"}
public type SystemPrompt record {|

    # The role or responsibility assigned to the agent
    @display {label: "Role"}
    string role;

    # Specific instructions for the agent
    @display {label: "Instructions"}
    string instructions;
|};

# Represents the authentication credentials of an autonomous agent.
@display {label: "Agent Credential"}
public type Credential record {|

    # The unique identifier assigned to the agent.
    @display {label: "Agent ID"}
    string id;

    # The secret associated with the agent.
    @display {label: "Agent Secret"}
    string secret;
|};

# Provides a set of configurations for the agent.
@display {label: "Agent Configuration"}
public type AgentConfiguration record {|

    # The system prompt assigned to the agent
    @display {label: "System Prompt"}
    SystemPrompt systemPrompt;

    # The model used by the agent
    @display {label: "Model"}
    ModelProvider model;

    # The tools available for the agent
    @display {label: "Tools"}
    (BaseToolKit|ToolConfig|FunctionTool)[] tools = [];

    # The maximum number of reasoning-action cycles the agent performs to complete the task.
    # A single cycle is one LLM call plus the execution of every tool call returned in
    # that response, so multiple tool calls from one response count as one iteration.
    # Defaults to `max(number of tools, 10)` — i.e., at least 10, or more if the
    # agent has more tools available.
    @display {label: "Maximum Iterations"}
    INFER_TOOL_COUNT|int maxIter = INFER_TOOL_COUNT;

    # Specifies whether verbose logging is enabled
    @display {label: "Verbose"}
    boolean verbose = false;

    # The memory used by the agent to store and manage conversation history.
    # Defaults to use an in-memory message store that trims on overflow, if unspecified.
    @display {label: "Memory"}
    Memory? memory?;

    # Defines the strategies for loading tool schemas into an Agent.
    # By default, all tools are loaded without any filtering.
    @display {label: "Tool Loading Strategy"}
    ToolLoadingStrategy toolLoadingStrategy = NO_FILTER;

    # Specifies whether multiple tool calls returned in a single LLM response are executed in parallel.
    # If `true`, all tool calls from one LLM response are executed concurrently;
    # otherwise, they are executed sequentially, one after another.
    @display {label: "Execute Tool Calls in Parallel"}
    boolean executeToolCallsInParallel = true;

    # Optional authentication details of the agent.
    @display {label: "Agent Credential"}
    Credential credential?;
|};

# Represents the supported agent type abstractions: an agent whose return type is inferred from the call
# site, or one that fixes its return type to a specific `anydata` value.
public type AgentType DependentlyTypedAgent|FixedTypedAgent;

# Represents the kind of a tool entry available to an agent.
public enum ToolKind {
    # A function or method tool
    FUNCTION_TOOL,
    # An MCP toolkit; its individual tools are resolved from the MCP server at runtime
    MCP_TOOLKIT,
    # Any other toolkit (e.g., an HTTP toolkit); its tools are resolved at runtime
    TOOLKIT
}

# Provides metadata about a single tool (or toolkit) available to a custom agent.
public type ToolMetadata record {|
    # The tool name. For toolkit entries this is the variable name used in the agent (or the
    # toolkit's type name when the toolkit is constructed inline).
    string name;
    # The kind of tool entry
    ToolKind kind;
    # The UI label from the tool's `@display` annotation, if present
    string label?;
    # The icon path from the tool's `@display` annotation, if present
    string icon?;
|};

# Identifies an `init` parameter of a custom agent definition through which a dependency is supplied.
public type ParameterInfo record {|
    # The name of the parameter in the `init` method's signature
    string parameterName;
|};

# Provides metadata about a custom agent definition.
# A compiler plugin records this for each custom agent (a class implementing `ai:AgentType`) within the
# `agentMetadata` field of the class's `@display` annotation, so consumers of a shared agent definition can
# discover its composition without access to the implementation. The recorded value lists the tools that are
# statically identifiable from the `ai:Agent` constructed in the class's `init` method, the agent's system
# prompt when resolvable, and the `init` parameters that supply the model provider and memory, if any.
public type AgentMetadataConfig record {|
    # The tools available to the agent
    ToolMetadata[] tools = [];
    # The system prompt of the composed agent. Present only when both the role and the instructions are
    # statically resolvable (string literals, interpolation-free string templates, or `const` references).
    SystemPrompt systemPrompt?;
    # The `init` parameter through which the agent's model provider is supplied.
    # Absent when the model is not injectable via the constructor (e.g., it is created internally).
    ParameterInfo modelProvider?;
    # The `init` parameter through which the agent's memory is supplied.
    # Absent when the memory is not injectable via the constructor.
    ParameterInfo memory?;
|};

# Represents an agent whose `run` return type is inferred from the expected type at the call site.
# Callers decide whether they want the full `Trace`, the raw `string` answer, or the answer bound 
# to a structured `anydata` type.
public type DependentlyTypedAgent distinct isolated object {
    # Executes the agent for the given query and binds the result to the inferred return type.
    #
    # + query - The query to be executed by the agent, as a plain string or a `Prompt` template
    # + sessionId - The ID associated with the agent memory
    # + context - The additional context that can be used during agent tool execution
    # + td - Type descriptor specifying the expected return type format
    # + return - The agent's response bound to `td`, or an `Error`
    public isolated function run(@display {label: "Query"} string|Prompt query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new,
            typedesc<Trace|anydata> td = <>) returns td|Error;
};

# Represents a reusable agent definition with a fixed `anydata` return type. Implementations typically
# compose an `Agent` and delegate to it, exposing a domain-specific return type from `run` while still
# surfacing the full execution `Trace` via `trace`.
public type FixedTypedAgent distinct isolated object {
    # Executes the agent for the given query and returns the result bound to the implementation's fixed type.
    #
    # + query - The query to be executed by the agent, as a plain string or a `Prompt` template
    # + sessionId - The ID associated with the agent memory
    # + context - The additional context that can be used during agent tool execution
    # + return - The agent's response as an `anydata` value, or an `Error`
    public isolated function run(@display {label: "Query"} string|Prompt query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new) returns anydata|Error;

    # Executes the agent for the given query and returns the full execution trace.
    #
    # + query - The query to be executed by the agent, as a plain string or a `Prompt` template
    # + sessionId - The ID associated with the agent memory
    # + context - The additional context that can be used during agent tool execution
    # + return - The execution `Trace`, or an `Error`
    public isolated function trace(@display {label: "Query"} string|Prompt query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new) returns Trace|Error;
};

# Represents an agent.
public isolated distinct class Agent {
    *DependentlyTypedAgent;

    # Tool store to be used by the agent
    final ToolStore toolStore;
    # LLM model instance (should be a function call model)
    final ModelProvider model;
    # The memory associated with the agent.
    final Memory memory;
    # Represents if the agent is stateless or not.
    final boolean stateless;
    # Strategy used to control how and when tools are loaded for the agent.
    final ToolLoadingStrategy toolLoadingStrategy;
    # Cache used to store and reuse authentication tokens for tool access.
    final cache:Cache tokenManager = new ();
    # Authentication configuration used for acquiring OAuth tokens when accessing secured tools.
    final readonly & Credential? agentCredential;
    # Indicates whether multiple tool calls from a single LLM response are executed in parallel.
    final boolean executeToolCallsInParallel;
    private final int maxIter;
    private final readonly & SystemPrompt systemPrompt;
    private final boolean verbose;
    private final string uniqueId = uuid:createRandomUuid();
    private final readonly & ToolSchema[] toolSchemas;
    private string? agentId = ();

    # Initialize an Agent.
    #
    # + config - Configuration used to initialize an agent
    public isolated function init(@display {label: "Agent Configuration"} *AgentConfiguration config) returns Error? {
        observe:CreateAgentSpan span = observe:createCreateAgentSpan(config.systemPrompt.role);
        span.addId(self.uniqueId);
        span.addSystemInstructions(getFomatedSystemPrompt(config.systemPrompt));

        INFER_TOOL_COUNT|int maxIter = config.maxIter;
        self.verbose = config.verbose;
        self.systemPrompt = config.systemPrompt.cloneReadOnly();
        Memory? memory = config.hasKey("memory") ? config?.memory : check new ShortTermMemory();
        observe:CreateAgentIdentitySpan? agentIdentitySpan = ();
        Credential? agentCredential = config.credential;
        if agentCredential is Credential {
            agentIdentitySpan = observe:createCreateAgentIdentitySpan(config.systemPrompt.role);
            self.agentId = agentCredential.id.cloneReadOnly();
            if agentIdentitySpan is observe:CreateAgentIdentitySpan {
                agentIdentitySpan.addId(agentCredential.id);
            }
        }
        do {
            self.toolStore = check new (...config.tools);
            self.model = config.model;
            self.memory = memory ?: check new ShortTermMemory();
            self.stateless = memory is ();
            self.toolLoadingStrategy = config.toolLoadingStrategy;
            self.executeToolCallsInParallel = config.executeToolCallsInParallel;
            self.agentCredential = agentCredential.cloneReadOnly();
            self.toolSchemas = self.toolStore.getToolSchema().cloneReadOnly();
            self.maxIter = maxIter is INFER_TOOL_COUNT ?
                int:max(self.toolSchemas.length(), DEFAULT_MINIMUM_MAX_ITERATIONS) : maxIter;
            span.addTools(self.toolStore.getToolsInfo());
            if agentIdentitySpan is observe:CreateAgentIdentitySpan {
                agentIdentitySpan.close();
            }
            span.close();
        } on fail Error err {
            if agentIdentitySpan is observe:CreateAgentIdentitySpan {
                agentIdentitySpan.close(err);
            }
            span.close(err);
            return err;
        }
    }

    # Use LLM to decide the next tool/step(s) based on the function calling APIs.
    #
    # + progress - Execution progress with the current query and execution history
    # + sessionId - The ID associated with the agent memory
    # + return - LLM response containing the tool calls or chat response (or an error if the call fails)
    isolated function selectNextTools(ExecutionProgress progress, string sessionId = DEFAULT_SESSION_ID)
            returns FunctionCall[]|string|Error {
        ChatMessage[] messages = check createFunctionCallMessages(progress);
        messages.unshift(...progress.history);
        ToolLoadingStrategy toolLoadingStrategy = self.toolLoadingStrategy;
        ChatMessage lastMessage = messages[messages.length() - 1];
        ChatCompletionFunctions[] registeredTools = from Tool tool in self.toolStore.tools.toArray()
            select {
                name: tool.name,
                description: tool.description,
                parameters: tool.variables
            };
        ChatCompletionFunctions[] filteredTools = registeredTools;
        if toolLoadingStrategy == LLM_FILTER && lastMessage is ChatUserMessage {
            ChatCompletionFunctions[]? selectedTools = lazyLoadTools(cloneMessages(messages), registeredTools, self.model);
            if selectedTools !is () {
                filteredTools = selectedTools;
            }
        }

        ResponseSchema? responseSchema = progress.responseSchema;
        if responseSchema is ResponseSchema {
            filteredTools.push(getStructuredOutputTool(responseSchema.schema));
        }

        log:printDebug("Requesting tool selection from LLM",
                executionId = progress.executionId,
                sessionId = sessionId,
                messages = messages.toString(),
                availableTools = filteredTools.toString()
        );

        ChatAssistantMessage response = check self.model->chat(messages, filteredTools);
        FunctionCall[]? toolCalls = getToolCalls(response);
        if toolCalls is FunctionCall[] {
            if responseSchema is ResponseSchema {
                foreach FunctionCall toolCall in toolCalls {
                    if toolCall.name == GET_RESULTS_TOOL {
                        log:printDebug("LLM returned the final answer via the structured-output tool",
                                executionId = progress.executionId,
                                sessionId = sessionId,
                                toolArguments = toolCall.arguments
                        );
                        return getStructuredAnswer(toolCall, responseSchema);
                    }
                }
            }
            log:printDebug("LLM selected tool(s)",
                    executionId = progress.executionId,
                    sessionId = sessionId,
                    toolNames = from FunctionCall toolCall in toolCalls select toolCall.name,
                    toolArguments = from FunctionCall toolCall in toolCalls select toolCall.arguments
            );
            return toolCalls;
        }

        log:printDebug("LLM provided chat response instead of tool call",
                executionId = progress.executionId,
                sessionId = sessionId,
                response = response?.content
        );
        string? content = response?.content;
        if content is string {
            return content;
        }
        log:printDebug("Failed to parse LLM response as valid tool or chat",
                agentId = self.agentId,
                executionId = progress.executionId,
                sessionId = sessionId
        );
        return error LlmInvalidGenerationError("Failed to parse the LLM response into a function call or chat message.",
            llmResponse = content);
    }

    # Executes the agent for a given user query.
    #
    # **Note:** Calls to this function using the same session ID must be invoked sequentially by the caller, 
    # as this operation is not thread-safe.
    #
    # + query - The natural language input provided to the agent
    # + sessionId - The ID associated with the agent memory
    # + context - The additional context that can be used during agent tool execution
    # + td - Type descriptor specifying the expected return type format
    # + return - The agent's response or an error
    public isolated function run(@display {label: "Query"} string|Prompt query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new,
            typedesc<Trace|anydata> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.stdlib.ai.Agent"
    } external;

    private isolated function runInternal(@display {label: "Query"} string|Prompt query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new, typedesc<Trace|anydata> td = string) returns Trace|anydata|Error {
        time:Utc startTime = time:utcNow();
        string executionId = uuid:createRandomUuid();
        string queryString = toString(query);
        log:printDebug("Agent execution started",
                executionId = executionId,
                agentId = self.agentId,
                query = queryString,
                sessionId = sessionId
        );

        observe:InvokeAgentSpan span = observe:createInvokeAgentSpan(self.systemPrompt.role);
        span.addId(self.uniqueId);
        span.addSessionId(sessionId);
        span.addInput(queryString);
        string systemPrompt = getFomatedSystemPrompt(self.systemPrompt);

        ResponseSchema? responseSchema = ();
        if td !is typedesc<string|Trace> && td is typedesc<anydata> {
            responseSchema = check getResponseSchemaForType(td);
            systemPrompt += getStructuredOutputInstruction();
        }
        span.addSystemInstruction(systemPrompt);

        Credential? & readonly agentCredential = self.agentCredential;
        string? agentId = agentCredential is Credential ? agentCredential.id : ();
        ExecutionTrace executionTrace = run(self, systemPrompt, query, self.maxIter, self.verbose, agentId,
                sessionId, context, executionId, responseSchema);
        ChatUserMessage userMessage = {role: USER, content: query};
        Iteration[] iterations = executionTrace.iterations;
        FunctionCall[]? toolCalls = executionTrace.toolCalls.length() == 0 ? () : executionTrace.toolCalls;
        do {
            string answer = check getAnswer(executionTrace);
            log:printDebug("Agent execution completed successfully",
                    executionId = executionId,
                    agentId = self.agentId,
                    steps = executionTrace.steps.toString(),
                    answer = answer
            );
            span.addOutput(observe:TEXT, answer);
            span.close();

            if td is typedesc<Trace> {
                return {
                    id: executionId,
                    userMessage,
                    iterations,
                    tools: self.toolSchemas,
                    startTime,
                    endTime: time:utcNow(),
                    output: {role: ASSISTANT, content: answer},
                    toolCalls
                };
            }
            if td is typedesc<string> {
                return answer;
            }
            if td is typedesc<anydata> {
                return parseAnswerAsType(answer, td);
            }
            return answer;
        } on fail Error err {
            log:printDebug("Agent execution failed",
                    err,
                    executionId = executionId,
                    agentId = self.agentId,
                    steps = executionTrace.steps.toString()
            );
            span.close(err);

            if td is typedesc<Trace> {
                return {
                    id: executionId,
                    userMessage,
                    iterations,
                    tools: self.toolSchemas,
                    startTime,
                    endTime: time:utcNow(),
                    output: err,
                    toolCalls
                };
            }
            return err;
        }
    }

}

# Builds the dedicated final-answer tool that carries the structured-output schema as its parameters.
#
# + parameters - JSON schema describing the expected final-answer structure
# + return - The final-answer tool definition
isolated function getStructuredOutputTool(map<json> parameters) returns ChatCompletionFunctions => {
    name: GET_RESULTS_TOOL,
    description: "Call this tool to deliver the final answer once the task is complete. " +
        "The answer must conform to the tool's parameter schema.",
    parameters
};

# Extracts the final answer from a structured-output tool call as a JSON string.
#
# + toolCall - The structured-output tool call returned by the model
# + responseSchema - The schema used to build the tool, indicating whether the type was wrapped
# + return - The final answer serialized as a JSON string
isolated function getStructuredAnswer(FunctionCall toolCall, ResponseSchema responseSchema) returns string {
    map<json> arguments = toolCall.arguments ?: {};
    json value = responseSchema.isOriginallyJsonObject ? arguments : arguments[RESULT];
    return value.toJsonString();
}

# Derives the structured-output schema for the expected return type. The schema is attached to the
# agent's final-answer tool so the model returns its answer as a schema-constrained tool call rather
# than free-form text.
#
# + td - Type descriptor specifying the expected return type
# + return - The response schema, or an error if a schema cannot be derived for the type
isolated function getResponseSchemaForType(typedesc<anydata> td) returns ResponseSchema|Error {
    typedesc<json>|error jsonTd = td.ensureType();
    if jsonTd is error {
        return error Error("Structured output is not supported for the expected return type", jsonTd);
    }
    return getExpectedResponseSchema(jsonTd);
}

# Builds the instruction, appended to the system prompt, that directs the agent to deliver its final
# answer by calling the structured-output tool instead of replying with free text.
#
# + return - The instruction text
isolated function getStructuredOutputInstruction() returns string =>
    "\n\nWhen you have determined the final answer, you must return it by calling the " +
    "`" + GET_RESULTS_TOOL + "` tool with the answer provided as its arguments. " +
    "Do not provide the final answer as plain text.";

# Parses the agent's final answer into a value of the expected type.
#
# + answer - The agent's final answer (expected to be a JSON value)
# + td - Type descriptor specifying the expected return type
# + return - The bound value, or an error if the answer cannot be parsed into the type
isolated function parseAnswerAsType(string answer, typedesc<anydata> td) returns anydata|Error {
    string trimmed = answer.trim();
    // Strip Markdown code fences (e.g. ```json ... ```) if the model added them.
    if trimmed.startsWith("```") {
        int? newlineIndex = trimmed.indexOf("\n");
        if newlineIndex is int {
            trimmed = trimmed.substring(newlineIndex + 1);
        }
        if trimmed.endsWith("```") {
            trimmed = trimmed.substring(0, trimmed.length() - 3);
        }
        trimmed = trimmed.trim();
    }
    anydata|error result = trimmed.fromJsonStringWithType(td);
    if result is error {
        return error Error(string `Failed to bind the agent's response to the expected type: ${result.message()}`,
                result);
    }
    return result;
}

isolated function getAnswer(ExecutionTrace executionTrace) returns string|Error {
    string? answer = executionTrace.answer;
    return answer ?: constructError(executionTrace);
}

isolated function constructError(ExecutionTrace executionTrace) returns Error {
    (ExecutionResult|ExecutionError|Error)[] steps = executionTrace.steps;
    if executionTrace.maxIterationsExceeded {
        return error MaxIterationExceededError("Maximum iteration limit exceeded while processing the query.",
            steps = steps);
    }
    // Validates whether the execution steps contain only one memory error.
    // If there is exactly one memory error, it is returned; otherwise, null is returned.
    if steps.length() == 1 {
        ExecutionResult|ExecutionError|Error step = steps[0];
        if step is ExecutionError && step.'error is MemoryError {
            return <MemoryError>step.'error;
        }
    }
    return error Error("Unable to obtain valid answer from the agent", steps = steps);
}

isolated function getFomatedSystemPrompt(SystemPrompt systemPrompt) returns string {
    return string `# Role  
${systemPrompt.role}  

# Instructions  
${systemPrompt.instructions}
`;
}
