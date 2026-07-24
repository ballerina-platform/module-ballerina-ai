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
    # Approval rule for every tool that requires human approval before execution, keyed by
    # tool name. A tool's own declaration (annotation or `ToolConfig`) takes precedence over an
    # entry with the same name in `ApprovalConfig.tools`.
    final readonly & map<RequiresApproval> approvalRules;
    # Optional expiry duration (in seconds) for a pending approval.
    final decimal? approvalTimeout;
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
            ApprovalConfig? approvalConfig = config.approval;
            self.approvalStore = approvalConfig?.store ?: new InMemoryApprovalStore();
            map<RequiresApproval> approvalRules = {};
            foreach Tool tool in self.toolStore.tools {
                if tool.requiresApproval !is false {
                    approvalRules[tool.name] = tool.requiresApproval;
                }
            }
            string[]|map<RequiresApproval> configApprovalTools = approvalConfig?.tools ?: [];
            if configApprovalTools is string[] {
                foreach string name in configApprovalTools {
                    if !approvalRules.hasKey(name) {
                        approvalRules[name] = true;
                    }
                }
            } else {
                foreach [string, RequiresApproval] [name, rule] in configApprovalTools.entries() {
                    if !approvalRules.hasKey(name) {
                        approvalRules[name] = rule;
                    }
                }
            }
            self.approvalRules = approvalRules.cloneReadOnly();
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

    # Use LLM to decide the next tool/step(s) based on the function calling APIs.
    #
    # + progress - Execution progress with the current query and execution history
    # + sessionId - The ID associated with the agent memory
    # + return - LLM response containing the tool or chat response (or an error if the call fails)
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

        log:printDebug("Requesting tool selection from LLM",
                executionId = progress.executionId,
                sessionId = sessionId,
                messages = messages.toString(),
                availableTools = filteredTools.toString()
        );

        ChatAssistantMessage response = check self.model->chat(messages, filteredTools);
        // All tool calls returned in this single LLM response are executed together
        // (see `Executor.next()`) before the LLM is consulted again, instead of executing
        // them one at a time across separate chat requests.
        FunctionCall[]? toolCalls = getToolCalls(response);
        if toolCalls is FunctionCall[] {
            log:printDebug("LLM selected tool(s)",
                    executionId = progress.executionId,
                    sessionId = sessionId,
                    toolNames = from FunctionCall toolCall in toolCalls
                        select toolCall.name,
                    toolArguments = from FunctionCall toolCall in toolCalls
                        select toolCall.arguments
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
    public isolated function run(@display {label: "Query"} string query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new,
            typedesc<Trace|string> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.stdlib.ai.Agent"
    } external;

    private isolated function runInternal(@display {label: "Query"} string query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new, boolean withTrace = false) returns string|Trace|Error {
        // A prior call on this session may still be awaiting a human decision. Starting a
        // fresh run regardless would silently orphan that pending approval (and, if this new
        // run also happens to pause, `approvalStore.put` would overwrite it outright) - so
        // check first, rather than let a new, unrelated turn interleave with an unresolved one.
        PendingApproval?|Error existingApprovalResult = self.approvalStore.get(sessionId);
        if existingApprovalResult is Error {
            return existingApprovalResult;
        }
        if existingApprovalResult is PendingApproval {
            if isApprovalExpired(existingApprovalResult) || !isPendingApprovalHistoryValid(existingApprovalResult) {
                log:printWarn("Clearing a stale pending approval to allow a new run", sessionId = sessionId);
                Error? removeErr = self.approvalStore.remove(sessionId);
                if removeErr is Error {
                    log:printError("Failed to remove the stale pending approval", removeErr, sessionId = sessionId);
                }
                // Fall through - proceed with a fresh run below.
            } else {
                return self.buildPendingApprovalTrace(existingApprovalResult, withTrace);
            }
        }

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
        return self.buildOutcome(executionId, userMessage, executionTrace, startTime, withTrace, span, sessionId,
            "Agent execution paused pending human approval",
            "Agent execution completed successfully",
            "Agent execution failed");
    }

    # Builds the `ApprovalRequiredError`/`Trace` for a still-live pending approval, without
    # starting a new run - used when `run()` is called again before the pending decision on
    # `sessionId` has been resolved, so the caller sees the same pause instead of silently
    # starting an unrelated turn that would orphan it.
    #
    # + pendingApproval - The still-live pending approval found for this session
    # + withTrace - Whether to wrap the result in a `Trace`
    # + return - The agent's response, wrapped in a `Trace` if `withTrace` is set, or an error
    private isolated function buildPendingApprovalTrace(PendingApproval pendingApproval, boolean withTrace)
            returns string|Trace|Error {
        ApprovalRequiredError stillPending = error ApprovalRequiredError(
            string `${pendingApproval.pendingRequests.length()} tool call(s) are still awaiting approval for ` +
                string `session '${pendingApproval.sessionId}'; call resume() before starting a new run.`,
            requests = pendingApproval.pendingRequests);
        // Safe: `isPendingApprovalHistoryValid` was already checked by the caller.
        ChatUserMessage userMessage =
            <ChatUserMessage>pendingApproval.history[pendingApproval.historyPrefixLength - 1];
        ExecutionTrace shortCircuitTrace = {
            steps: [],
            iterations: pendingApproval.iterations,
            toolCalls: pendingApproval.toolCalls,
            pendingApproval: stillPending
        };
        observe:InvokeAgentSpan span = observe:createInvokeAgentSpan(self.systemPrompt.role);
        span.addId(self.uniqueId);
        span.addSessionId(pendingApproval.sessionId);
        return self.buildOutcome(pendingApproval.executionId, userMessage, shortCircuitTrace,
            pendingApproval.startTime, withTrace, span, pendingApproval.sessionId,
            "Agent execution already has a pending approval; run() was called again before resume()",
            "", "");
    }

    # Resumes a run that paused for human approval on `sessionId`.
    #
    # `feedback` is a map of decisions keyed by each request's `ApprovalRequest.id` - always a
    # map, even when only one call is pending, since there is no way to know in advance how many
    # tool calls an LLM turn will propose or how many of them will need approval. A partial map
    # (fewer entries than there are pending requests) is fine - whatever isn't supplied stays
    # pending, and this call returns a fresh `ApprovalRequiredError` listing just the
    # still-undecided requests.
    #
    # **Note:** like `run`, calls for the same session ID must be sequential.
    #
    # + sessionId - The ID associated with the agent memory
    # + feedback - The human's decisions, keyed by `ApprovalRequest.id`
    # + context - The additional context that can be used during agent tool execution
    # + td - Type descriptor specifying the expected return type format
    # + return - The agent's response or an error
    public isolated function resume(@display {label: "Session ID"} string sessionId,
            @display {label: "Human Feedback"} map<HumanFeedback> feedback,
            Context context = new,
            typedesc<Trace|string> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.stdlib.ai.Agent"
    } external;

    # Returns the approvals currently pending on `sessionId`, if any.
    #
    # + sessionId - The ID associated with the agent memory
    # + return - Every currently pending approval request, `()` if none is pending, or an `ai:Error`
    public isolated function getPendingApproval(string sessionId) returns ApprovalRequest[]?|Error {
        PendingApproval?|Error pendingApprovalResult = self.approvalStore.get(sessionId);
        if pendingApprovalResult is Error {
            return pendingApprovalResult;
        }
        if pendingApprovalResult is () || isApprovalExpired(pendingApprovalResult)
                || !isPendingApprovalHistoryValid(pendingApprovalResult) {
            return ();
        }
        return pendingApprovalResult.pendingRequests;
    }

    private isolated function resumeInternal(string sessionId, map<HumanFeedback> feedback,
            Context context = new, boolean withTrace = false) returns string|Trace|Error {
        log:printDebug("Agent resume started",
                agentId = self.agentId,
                sessionId = sessionId
        );

        // Claimed eagerly (removed from the store immediately, not just on resolution), so a
        // concurrent duplicate `resume()` call for the same session finds nothing and fails
        // fast with `ApprovalNotFoundError` instead of also executing the approved tool call.
        // `executeAgentLoop`'s pause branch already unconditionally re-persists a fresh
        // `PendingApproval` if this call pauses again (e.g. another gate still undecided in the
        // same batch), so claiming here composes correctly with that existing flow.
        PendingApproval?|Error pendingApprovalResult = self.approvalStore.take(sessionId);
        if pendingApprovalResult is Error {
            return pendingApprovalResult;
        }
        if pendingApprovalResult is () {
            return error ApprovalNotFoundError("No pending approval found for session '" + sessionId + "'.");
        }
        PendingApproval pendingApproval = pendingApprovalResult;
        if isApprovalExpired(pendingApproval) {
            // Already removed by `take()` above - nothing more to clean up.
            return error ApprovalExpiredError("The pending approval for session '" + sessionId + "' has expired.");
        }
        if !isPendingApprovalHistoryValid(pendingApproval) {
            log:printError("Pending approval has an invalid history snapshot",
                    sessionId = sessionId,
                    historyLength = pendingApproval.history.length(),
                    historyPrefixLength = pendingApproval.historyPrefixLength
            );
            return error Error("The pending approval for session '" + sessionId + "' has a corrupted history " +
                    "snapshot and cannot be resumed. This should never happen with the built-in " +
                    "`InMemoryApprovalStore`; check any custom `ApprovalStore` implementation in use.");
        }

        // Not the claimed record's fault - nothing was actually resolved - so restore it
        // before returning, rather than leaving it lost after a caller mistake.
        string[] unknownIds = findUnknownApprovalIds(feedback, pendingApproval.pendingRequests);
        if unknownIds.length() > 0 {
            self.restoreClaimedApproval(pendingApproval, sessionId);
            return error UnknownApprovalIdError(
                    string `The following ids are not currently pending for session '${sessionId}': ` +
                        unknownIds.toString());
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
        ExecutionTrace executionTrace = resumeRun(self, pendingApproval, feedback, self.maxIter,
            self.verbose, agentId, sessionId, context);
        // Safe: `isPendingApprovalHistoryValid` above already guarantees this index is in range.
        ChatUserMessage userMessage = <ChatUserMessage>pendingApproval.history[pendingApproval.historyPrefixLength - 1];
        return self.buildOutcome(executionId, userMessage, executionTrace, startTime, withTrace, span, sessionId,
            "Agent execution paused again pending human approval",
            "Agent resume completed successfully",
            "Agent resume failed");
    }

    # Re-persists a `PendingApproval` claimed by `take()` when a `resume()` call names an unknown
    # id before anything was actually resolved, so the caller can simply retry `resume()` with a
    # corrected decision instead of losing the pause.
    #
    # + pendingApproval - The claimed pending approval to restore, unchanged
    # + sessionId - The ID associated with the agent memory
    private isolated function restoreClaimedApproval(PendingApproval pendingApproval, string sessionId) {
        Error? restoreErr = self.approvalStore.put(pendingApproval);
        if restoreErr is Error {
            log:printError("Failed to restore the claimed pending approval after an invalid resume() call",
                    restoreErr, sessionId = sessionId);
        }
    }

    # Shared by `runInternal`/`resumeInternal`: turns an `ExecutionTrace` into the agent's public
    # `string|Trace|Error` result - a pause passthrough, a successful answer, or a failure - all
    # three optionally wrapped in a `Trace` when the caller requested `withTrace`.
    #
    # + executionId - Identifier of the logical execution this outcome belongs to
    # + userMessage - The turn's user message, for the returned `Trace`
    # + executionTrace - The trace produced by `run`/`resumeRun` for this call
    # + startTime - The logical run's start time, for the returned `Trace`
    # + withTrace - Whether to wrap the result in a `Trace`
    # + span - Observability span for this call, closed with the outcome
    # + sessionId - The ID associated with the agent memory
    # + pauseLogMessage - Message logged when the execution paused for human approval
    # + successLogMessage - Message logged when the execution completed successfully
    # + failedLogMessage - Message logged when the execution failed
    # + return - The agent's response, wrapped in a `Trace` if `withTrace` is set, or an error
    private isolated function buildOutcome(string executionId, ChatUserMessage userMessage,
            ExecutionTrace executionTrace, time:Utc startTime, boolean withTrace, observe:InvokeAgentSpan span,
            string sessionId, string pauseLogMessage, string successLogMessage,
            string failedLogMessage) returns string|Trace|Error {
        Iteration[] iterations = executionTrace.iterations;
        FunctionCall[]? toolCalls = executionTrace.toolCalls.length() == 0 ? () : executionTrace.toolCalls;

        ApprovalRequiredError? pendingApproval = executionTrace.pendingApproval;
        if pendingApproval is ApprovalRequiredError {
            log:printDebug(pauseLogMessage,
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
            string answer = check getAnswer(executionTrace);
            log:printDebug(successLogMessage,
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
            log:printDebug(failedLogMessage,
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

// A batch pause is treated as expired as soon as any one of its still-pending requests has
// expired, even if the others haven't yet: every gated call in the batch was requested within
// the same turn under the same timeout, so letting only some of them survive would leave the
// batch in a state where it can never be fully resolved (the expired one can never gather a
// valid decision) but also never gets cleaned up on its own.
isolated function isApprovalExpired(PendingApproval pendingApproval) returns boolean {
    foreach ApprovalRequest request in pendingApproval.pendingRequests {
        time:Utc? expiresAt = request?.expiresAt;
        if expiresAt is time:Utc && time:utcDiffSeconds(time:utcNow(), expiresAt) > 0d {
            return true;
        }
    }
    return false;
}

// `history` must contain, in order, a system message followed by a user message before the
// prefix ends (`run` always appends both - see `agent-utils.bal`), so a valid snapshot has
// `historyPrefixLength >= 2`. The prefix may equal `history.length()` when the very first tool
// call proposed is the one that paused, so `<=` (not `<`) is the correct upper bound.
isolated function isPendingApprovalHistoryValid(PendingApproval pendingApproval) returns boolean {
    int historyPrefixLength = pendingApproval.historyPrefixLength;
    return historyPrefixLength >= 2 && historyPrefixLength <= pendingApproval.history.length();
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
