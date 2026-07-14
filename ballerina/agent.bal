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

# Represents the different types of agents supported by the module.
@display {label: "Agent Type"}
public enum AgentType {
    # Represents a ReAct agent
    REACT_AGENT,
    # Represents a function call agent
    FUNCTION_CALL_AGENT
}

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

    # The maximum number of iterations the agent performs to complete the task.
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

    # Optional authentication details of the agent.
    @display {label: "Agent Credential"}
    Credential credential?;

    # Human-in-the-loop configuration.
    @display {label: "Human-in-the-loop Configuration"}
    ApprovalConfig approval?;
|};

# Represents an agent.
public isolated distinct class Agent {
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
    # Store used to persist pending human approvals across pause/resume.
    final ApprovalStore approvalStore;
    # Names of tools that require human approval before execution.
    final readonly & string[] approvalTools;
    # Optional expiry duration (in seconds) for a pending approval.
    final decimal? approvalTimeout;
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
            self.agentCredential = agentCredential.cloneReadOnly();
            self.toolSchemas = self.toolStore.getToolSchema().cloneReadOnly();
            self.maxIter = maxIter is INFER_TOOL_COUNT ?
                int:max(self.toolSchemas.length(), DEFAULT_MINIMUM_MAX_ITERATIONS) : maxIter;
            ApprovalConfig? approvalConfig = config.approval;
            self.approvalStore = approvalConfig?.store ?: new InMemoryApprovalStore();
            string[] annotatedApprovalTools = from Tool tool in self.toolStore.tools
                where tool.requiresApproval
                select tool.name;
            self.approvalTools = [...annotatedApprovalTools, ...(approvalConfig?.tools ?: [])].cloneReadOnly();
            self.approvalTimeout = approvalConfig?.timeout;
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

    # Parse the function calling API response and extract the tool to be executed.
    #
    # + llmResponse - Raw LLM response
    # + return - A record containing the tool decided by the LLM, chat response or an error if the response is invalid
    isolated function parseLlmResponse(json llmResponse) returns LlmToolResponse|LlmChatResponse|LlmInvalidGenerationError {
        if llmResponse is string {
            return {content: llmResponse};
        }
        if llmResponse !is FunctionCall {
            return error LlmInvalidGenerationError("Invalid response", llmResponse = llmResponse);
        }
        string? name = llmResponse.name;
        if name is () {
            return error LlmInvalidGenerationError("Missing name", name = llmResponse.name, arguments = llmResponse.arguments);
        }
        return {
            name,
            arguments: llmResponse.arguments,
            id: llmResponse.id
        };
    }

    # Use LLM to decide the next tool/step based on the function calling APIs.
    #
    # + progress - Execution progress with the current query and execution history
    # + sessionId - The ID associated with the agent memory
    # + return - LLM response containing the tool or chat response (or an error if the call fails)
    isolated function selectNextTool(ExecutionProgress progress, string sessionId = DEFAULT_SESSION_ID) returns json|Error {
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

        log:printDebug("Requesting tool selection from LLM",
                executionId = progress.executionId,
                sessionId = sessionId,
                messages = messages.toString(),
                availableTools = filteredTools.toString()
        );

        // TODO: Improve handling of multiple tool calls returned by the LLM.
        // Currently, tool calls are executed sequentially in separate chat responses.
        // Update the logic to execute all tool calls together and return a single response.
        ChatAssistantMessage response = check self.model->chat(messages, filteredTools);
        FunctionCall? toolCall = getFirstToolCall(response);

        if toolCall is FunctionCall {
            log:printDebug("LLM selected tool",
                    executionId = progress.executionId,
                    sessionId = sessionId,
                    toolName = toolCall.name,
                    toolArguments = toolCall.arguments
            );
            return toolCall;
        }

        log:printDebug("LLM provided chat response instead of tool call",
                executionId = progress.executionId,
                sessionId = sessionId,
                response = response?.content
        );
        return response?.content;
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
    public isolated function run(@display {label: "Query"} string query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new,
            typedesc<Trace|string> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.stdlib.ai.Agent"
    } external;

    private isolated function runInternal(@display {label: "Query"} string query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new, boolean withTrace = false) returns string|Trace|Error {
        time:Utc startTime = time:utcNow();
        string executionId = uuid:createRandomUuid();
        log:printDebug("Agent execution started",
                executionId = executionId,
                agentId = self.agentId,
                query = query,
                sessionId = sessionId
        );

        observe:InvokeAgentSpan span = observe:createInvokeAgentSpan(self.systemPrompt.role);
        span.addId(self.uniqueId);
        span.addSessionId(sessionId);
        span.addInput(query);
        string systemPrompt = getFomatedSystemPrompt(self.systemPrompt);
        span.addSystemInstruction(systemPrompt);

        Credential? & readonly agentCredential = self.agentCredential;
        string? agentId = agentCredential is Credential ? agentCredential.id : ();
        ExecutionTrace executionTrace = run(self, systemPrompt, query, self.maxIter, self.verbose, agentId,
            sessionId, context, executionId, startTime);
        ChatUserMessage userMessage = {role: USER, content: query};
        Iteration[] iterations = executionTrace.iterations;
        FunctionCall[]? toolCalls = executionTrace.toolCalls.length() == 0 ? () : executionTrace.toolCalls;

        ApprovalRequiredError? pendingApproval = executionTrace.pendingApproval;
        if pendingApproval is ApprovalRequiredError {
            log:printDebug("Agent execution paused pending human approval",
                    executionId = executionId,
                    agentId = self.agentId,
                    sessionId = sessionId
            );
            span.close(pendingApproval);
            return withTrace
                ? {
                    id: executionId,
                    userMessage,
                    iterations,
                    tools: self.toolSchemas,
                    startTime,
                    endTime: time:utcNow(),
                    output: pendingApproval,
                    toolCalls
                }
                : pendingApproval;
        }
        do {
            string answer = check getAnswer(executionTrace, self.maxIter);
            log:printDebug("Agent execution completed successfully",
                    executionId = executionId,
                    agentId = self.agentId,
                    steps = executionTrace.steps.toString(),
                    answer = answer
            );
            span.addOutput(observe:TEXT, answer);
            span.close();

            return withTrace
                ? {
                    id: executionId,
                    userMessage,
                    iterations,
                    tools: self.toolSchemas,
                    startTime,
                    endTime: time:utcNow(),
                    output: {role: ASSISTANT, content: answer},
                    toolCalls
                }
                : answer;
        } on fail Error err {
            log:printDebug("Agent execution failed",
                    err,
                    executionId = executionId,
                    agentId = self.agentId,
                    steps = executionTrace.steps.toString()
            );
            span.close(err);

            return withTrace
                ? {
                    id: executionId,
                    userMessage,
                    iterations,
                    tools: self.toolSchemas,
                    startTime,
                    endTime: time:utcNow(),
                    output: err,
                    toolCalls
                }
                : err;
        }
    }

    # Resumes a run that paused for human approval on `sessionId`.
    #
    # **Note:** like `run`, calls for the same session ID must be sequential.
    #
    # + sessionId - The ID associated with the agent memory
    # + feedback - The human's decision on the pending tool call
    # + context - The additional context that can be used during agent tool execution
    # + td - Type descriptor specifying the expected return type format
    # + return - The agent's response or an error
    public isolated function resume(@display {label: "Session ID"} string sessionId,
            @display {label: "Human Feedback"} HumanFeedback feedback,
            Context context = new,
            typedesc<Trace|string> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.stdlib.ai.Agent"
    } external;

    # Returns the approval currently pending on `sessionId`, if any.
    #
    # + sessionId - The ID associated with the agent memory
    # + return - The pending approval request, `()` if none is pending, or an `ai:Error`
    public isolated function getPendingApproval(string sessionId) returns ApprovalRequest?|Error {
        PendingApproval?|Error pendingApprovalResult = self.approvalStore.get(sessionId);
        if pendingApprovalResult is Error {
            return pendingApprovalResult;
        }
        if pendingApprovalResult is () || isApprovalExpired(pendingApprovalResult) {
            return ();
        }
        PendingApproval {id, sessionId: sid, toolName, toolDescription, arguments, toolCallId, requestedAt,
                expiresAt} = pendingApprovalResult;
        ApprovalRequest request = {id, sessionId: sid, toolName, toolDescription, arguments, toolCallId,
                requestedAt, expiresAt};
        return request;
    }

    private isolated function resumeInternal(string sessionId, HumanFeedback feedback,
            Context context = new, boolean withTrace = false) returns string|Trace|Error {
        log:printDebug("Agent resume started",
                agentId = self.agentId,
                sessionId = sessionId
        );

        PendingApproval?|Error pendingApprovalResult = self.approvalStore.get(sessionId);
        if pendingApprovalResult is Error {
            return pendingApprovalResult;
        }
        if pendingApprovalResult is () {
            return error ApprovalNotFoundError("No pending approval found for session '" + sessionId + "'.");
        }
        PendingApproval pendingApproval = pendingApprovalResult;
        if isApprovalExpired(pendingApproval) {
            Error? removeErr = self.approvalStore.remove(sessionId);
            if removeErr is Error {
                log:printError("Failed to remove the expired pending approval", removeErr, sessionId = sessionId);
            }
            return error ApprovalExpiredError("The pending approval for session '" + sessionId + "' has expired.");
        }
        if !isPendingApprovalHistoryValid(pendingApproval) {
            Error? removeErr = self.approvalStore.remove(sessionId);
            if removeErr is Error {
                log:printError("Failed to remove the corrupted pending approval", removeErr, sessionId = sessionId);
            }
            log:printError("Pending approval has an invalid history snapshot",
                    sessionId = sessionId,
                    historyLength = pendingApproval.history.length(),
                    historyPrefixLength = pendingApproval.historyPrefixLength
            );
            return error Error("The pending approval for session '" + sessionId + "' has a corrupted history " +
                    "snapshot and cannot be resumed. This should never happen with the built-in " +
                    "`InMemoryApprovalStore`; check any custom `ApprovalStore` implementation in use.");
        }

        // Carry the original run's start time forward, so `Trace.startTime` reflects the
        // whole logical run rather than just this resume call.
        time:Utc startTime = pendingApproval.startTime;
        string executionId = pendingApproval.executionId;
        observe:InvokeAgentSpan span = observe:createInvokeAgentSpan(self.systemPrompt.role);
        span.addId(self.uniqueId);
        span.addSessionId(sessionId);

        Credential? & readonly agentCredential = self.agentCredential;
        string? agentId = agentCredential is Credential ? agentCredential.id : ();
        ExecutionTrace executionTrace = resumeRun(self, pendingApproval, feedback, self.maxIter, self.verbose,
            agentId, sessionId, context);
        // Safe: `isPendingApprovalHistoryValid` above already guarantees this index is in range.
        ChatUserMessage userMessage = <ChatUserMessage>pendingApproval.history[pendingApproval.historyPrefixLength - 1];
        Iteration[] iterations = executionTrace.iterations;
        FunctionCall[]? toolCalls = executionTrace.toolCalls.length() == 0 ? () : executionTrace.toolCalls;

        ApprovalRequiredError? nextPendingApproval = executionTrace.pendingApproval;
        if nextPendingApproval is ApprovalRequiredError {
            log:printDebug("Agent execution paused again pending human approval",
                    executionId = executionId,
                    agentId = self.agentId,
                    sessionId = sessionId
            );
            span.close(nextPendingApproval);
            return withTrace
                ? {
                    id: executionId,
                    userMessage,
                    iterations,
                    tools: self.toolSchemas,
                    startTime,
                    endTime: time:utcNow(),
                    output: nextPendingApproval,
                    toolCalls
                }
                : nextPendingApproval;
        }

        do {
            string answer = check getAnswer(executionTrace, self.maxIter);
            Error? removeErr = self.approvalStore.remove(sessionId);
            if removeErr is Error {
                log:printError("Failed to remove the resolved pending approval", removeErr, sessionId = sessionId);
            }
            log:printDebug("Agent resume completed successfully",
                    executionId = executionId,
                    agentId = self.agentId,
                    steps = executionTrace.steps.toString(),
                    answer = answer
            );
            span.addOutput(observe:TEXT, answer);
            span.close();

            return withTrace
                ? {
                    id: executionId,
                    userMessage,
                    iterations,
                    tools: self.toolSchemas,
                    startTime,
                    endTime: time:utcNow(),
                    output: {role: ASSISTANT, content: answer},
                    toolCalls
                }
                : answer;
        } on fail Error err {
            Error? removeErr = self.approvalStore.remove(sessionId);
            if removeErr is Error {
                log:printError("Failed to remove the resolved pending approval", removeErr, sessionId = sessionId);
            }
            log:printDebug("Agent resume failed",
                    err,
                    executionId = executionId,
                    agentId = self.agentId,
                    steps = executionTrace.steps.toString()
            );
            span.close(err);

            return withTrace
                ? {
                    id: executionId,
                    userMessage,
                    iterations,
                    tools: self.toolSchemas,
                    startTime,
                    endTime: time:utcNow(),
                    output: err,
                    toolCalls
                }
                : err;
        }
    }
}

isolated function isApprovalExpired(PendingApproval pendingApproval) returns boolean {
    time:Utc? expiresAt = pendingApproval?.expiresAt;
    return expiresAt is time:Utc && time:utcDiffSeconds(time:utcNow(), expiresAt) > 0d;
}

// `history` must contain, in order, a system message followed by a user message before the
// prefix ends (`run` always appends both - see `agent-utils.bal`), so a valid snapshot has
// `historyPrefixLength >= 2`. The prefix may equal `history.length()` when the very first tool
// call proposed is the one that paused, so `<=` (not `<`) is the correct upper bound.
isolated function isPendingApprovalHistoryValid(PendingApproval pendingApproval) returns boolean {
    int historyPrefixLength = pendingApproval.historyPrefixLength;
    return historyPrefixLength >= 2 && historyPrefixLength <= pendingApproval.history.length();
}

isolated function getAnswer(ExecutionTrace executionTrace, int maxIter) returns string|Error {
    string? answer = executionTrace.answer;
    return answer ?: constructError(executionTrace.steps, executionTrace.iterationsUsed, maxIter);
}

isolated function constructError((ExecutionResult|ExecutionError|Error)[] steps, int iterationsUsed, int maxIter)
        returns Error {
    // `iterationsUsed` is the true iteration counter for the whole logical run (correct even
    // after a resume, when `steps` only holds the current call's own steps and would otherwise
    // never match `maxIter`).
    if (iterationsUsed == maxIter) {
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
