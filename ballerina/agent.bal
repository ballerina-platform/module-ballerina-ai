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
const STRUCTURED_OUTPUT_TOOL = "__ballerina_ai_structured_result__";

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
    # Pass a `string`/`Prompt` to start a new turn, or a `Resume` (the human's decisions on a
    # previously paused run) to continue a run that paused for human approval. The input type is
    # what distinguishes the two - there is no separate resume operation.
    #
    # + query - A query to start a new turn (`string`/`Prompt`), or a `Resume` to continue a paused run
    # + sessionId - The ID associated with the agent memory
    # + context - The additional context that can be used during agent tool execution
    # + td - Type descriptor specifying the expected return type format
    # + return - The agent's response bound to `td`, or an `Error`
    public isolated function run(@display {label: "Query"} string|Prompt|Resume query,
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
    # Persists HITL pause checkpoints. The configured `memory` itself when it is a
    # `ShortTermMemory` (which persists checkpoints in its store), otherwise a private in-memory
    # `ShortTermMemory` fallback that is not durable across a restart or a run on another replica.
    final ShortTermMemory checkpointer;
    # Approval rule for every tool that requires human approval before execution, keyed by tool
    # name. A rule comes from the tool's own declaration - the `@ai:AgentTool {requiresApproval}`
    # annotation or `ToolConfig.requiresApproval`.
    final readonly & map<RequiresApproval> approvalRules;
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
            map<RequiresApproval> approvalRules = {};
            foreach Tool tool in self.toolStore.tools {
                if tool.requiresApproval !is false {
                    approvalRules[tool.name] = tool.requiresApproval;
                }
            }
            self.approvalRules = approvalRules.cloneReadOnly();
            // The HITL pause checkpoint is persisted through `memory` when it is a
            // `ShortTermMemory` (which persists checkpoints in its configured store), so a single
            // configured store serves both the conversation history and the pause state.
            // Otherwise fall back to a private in-memory `ShortTermMemory`, warning if any tool can
            // actually gate, since pauses then won't survive a restart or a run on another replica.
            Memory agentMemory = self.memory;
            if agentMemory is ShortTermMemory {
                self.checkpointer = agentMemory;
            } else {
                self.checkpointer = check new ShortTermMemory();
                if approvalRules.length() > 0 {
                    log:printWarn("The configured memory does not support durable checkpointing; " +
                        "human-in-the-loop pauses will not survive a restart or run on another " +
                        "replica. Use `ShortTermMemory` for durable human-in-the-loop.");
                }
            }
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
                    if toolCall.name == STRUCTURED_OUTPUT_TOOL {
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

    # Executes the agent for a given query.
    #
    # Pass a `string`/`Prompt` to start a new turn, or a `Resume` (the human's decisions on a
    # previously paused run) to continue a run that paused for human approval on this session. The
    # input type is what distinguishes a fresh turn from a resume - there is no separate resume
    # operation. A `Resume` for a session with no pending approval fails with `ApprovalNotFoundError`.
    #
    # **Note:** Calls to this function using the same session ID must be invoked sequentially by the caller,
    # as this operation is not thread-safe.
    #
    # + query - A query to start a new turn (`string`/`Prompt`), or a `Resume` to continue a paused run
    # + sessionId - The ID associated with the agent memory
    # + context - The additional context that can be used during agent tool execution
    # + td - Type descriptor specifying the expected return type format
    # + return - The agent's response or an error
    public isolated function run(@display {label: "Query"} string|Prompt|Resume query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new,
            typedesc<Trace|anydata> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.stdlib.ai.Agent"
    } external;

    private isolated function runInternal(@display {label: "Query"} string|Prompt|Resume query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new, typedesc<Trace|anydata> td = string) returns Trace|anydata|Error {
        // A `Resume` input continues a run that paused for human approval instead of starting a
        // new turn; the input type is the sole discriminator between the two.
        if query is Resume {
            return self.resumeInternal(sessionId, query.decisions, context, td);
        }
        // A prior call on this session may still be awaiting a human decision. Starting a
        // fresh run regardless would silently orphan that pending approval (and, if this new
        // run also happens to pause, `checkpointer.put` would overwrite it outright) - so
        // check first, rather than let a new, unrelated turn interleave with an unresolved one.
        PendingApproval?|Error existingApprovalResult = self.checkpointer.getCheckpoint(sessionId);
        if existingApprovalResult is Error {
            // Trace this earliest guard failure too, matching how `resumeInternal` opens its span
            // before its own guards - otherwise a checkpoint-store failure here goes unobserved.
            observe:InvokeAgentSpan errorSpan = observe:createInvokeAgentSpan(self.systemPrompt.role);
            errorSpan.addId(self.uniqueId);
            errorSpan.addSessionId(sessionId);
            errorSpan.close(existingApprovalResult);
            return existingApprovalResult;
        }
        if existingApprovalResult is PendingApproval {
            if !isPendingApprovalHistoryValid(existingApprovalResult) {
                log:printWarn("Clearing a corrupted pending approval to allow a new run", sessionId = sessionId);
                Error? removeErr = self.checkpointer.removeCheckpoint(sessionId);
                if removeErr is Error {
                    log:printError("Failed to remove the corrupted pending approval", removeErr, sessionId = sessionId);
                }
                // Fall through - proceed with a fresh run below.
            } else {
                return self.buildPendingApprovalTrace(existingApprovalResult, td, toString(query));
            }
        }

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
            ResponseSchema|Error schema = getResponseSchemaForType(td);
            if schema is Error {
                span.close(schema);
                return schema;
            }
            responseSchema = schema;
            systemPrompt += getStructuredOutputInstruction();
        }
        span.addSystemInstruction(systemPrompt);

        Credential? & readonly agentCredential = self.agentCredential;
        string? agentId = agentCredential is Credential ? agentCredential.id : ();
        ExecutionTrace executionTrace = run(self, systemPrompt, query, self.maxIter, self.verbose, agentId,
            sessionId, context, executionId, startTime, responseSchema);
        ChatUserMessage userMessage = {role: USER, content: query};
        return self.buildOutcome(executionId, userMessage, executionTrace, startTime, td, span, sessionId,
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
    # + td - Type descriptor specifying the expected return type format
    # + attemptedQuery - The new query that was rejected because a pause is still outstanding,
    #                    recorded on the span so the short-circuited attempt is visible in the trace
    # + return - The agent's response bound to `td`, or an error
    private isolated function buildPendingApprovalTrace(PendingApproval pendingApproval,
            typedesc<Trace|anydata> td, string attemptedQuery) returns Trace|anydata|Error {
        ApprovalRequiredError stillPending = error ApprovalRequiredError(
            string `${pendingApproval.pendingRequests.length()} tool call(s) are still awaiting approval for ` +
                string `session '${pendingApproval.sessionId}'; resume it (pass a Resume) before starting a new run.`,
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
        span.addInput(attemptedQuery);
        return self.buildOutcome(pendingApproval.executionId, userMessage, shortCircuitTrace,
            pendingApproval.startTime, td, span, pendingApproval.sessionId,
            "Agent execution already has a pending approval; a new run was started before it was resumed",
            "", "");
    }

    # Continues a run that paused for human approval on `sessionId`, applying the supplied decisions.
    # Reached from `run` when its input is a `Resume`; not a public entry point of its own.
    #
    # + sessionId - The ID associated with the agent memory
    # + feedback - The human's decisions, keyed by `ApprovalRequest.id`
    # + context - The additional context that can be used during agent tool execution
    # + td - Type descriptor specifying the expected return type format
    # + return - The agent's response bound to `td`, or an error
    private isolated function resumeInternal(string sessionId, map<HumanResponse> feedback,
            Context context = new, typedesc<Trace|anydata> td = string) returns Trace|anydata|Error {
        log:printDebug("Agent resume started",
                agentId = self.agentId,
                sessionId = sessionId
        );

        // Opened before the guard checks below so a rejected resume (no pending approval, corrupted
        // state, unknown id) still produces one errored span, matching how the fresh-run path traces
        // its own early failures (e.g. a bad `td` schema).
        observe:InvokeAgentSpan span = observe:createInvokeAgentSpan(self.systemPrompt.role);
        span.addId(self.uniqueId);
        span.addSessionId(sessionId);
        // A resume has no query; its input is the human's decisions. Recorded before the guards
        // so even a rejected resume's span shows which decisions were attempted.
        span.addInput(string `resume decisions: ${feedback.toJsonString()}`);

        // Claimed eagerly (removed from the store immediately, not just on resolution), so a
        // concurrent duplicate resume for the same session finds nothing and fails
        // fast with `ApprovalNotFoundError` instead of also executing the approved tool call.
        // `executeAgentLoop`'s pause branch already unconditionally re-persists a fresh
        // `PendingApproval` if this call pauses again (e.g. another gate still undecided in the
        // same batch), so claiming here composes correctly with that existing flow.
        PendingApproval?|Error pendingApprovalResult = self.checkpointer.takeCheckpoint(sessionId);
        if pendingApprovalResult is Error {
            span.close(pendingApprovalResult);
            return pendingApprovalResult;
        }
        if pendingApprovalResult is () {
            ApprovalNotFoundError notFound =
                error ApprovalNotFoundError("No pending approval found for session '" + sessionId + "'.");
            span.close(notFound);
            return notFound;
        }
        PendingApproval pendingApproval = pendingApprovalResult;
        if !isPendingApprovalHistoryValid(pendingApproval) {
            log:printError("Pending approval has an invalid history snapshot",
                    sessionId = sessionId,
                    historyLength = pendingApproval.history.length(),
                    historyPrefixLength = pendingApproval.historyPrefixLength
            );
            Error corrupted =
                error Error("The pending approval for session '" + sessionId + "' has a corrupted history " +
                    "snapshot and cannot be resumed. This should never happen with the built-in " +
                    "`ShortTermMemory`; check any custom `ShortTermMemoryStore` implementation in use.");
            span.close(corrupted);
            return corrupted;
        }

        // Not the claimed record's fault - nothing was actually resolved - so restore it
        // before returning, rather than leaving it lost after a caller mistake.
        string[] unknownIds = findUnknownApprovalIds(feedback, pendingApproval.pendingRequests);
        if unknownIds.length() > 0 {
            self.restoreClaimedApproval(pendingApproval, sessionId);
            UnknownApprovalIdError unknown = error UnknownApprovalIdError(
                    string `The following ids are not currently pending for session '${sessionId}': ` +
                        unknownIds.toString());
            span.close(unknown);
            return unknown;
        }

        // Emit a dedicated child span so the human's decisions are visible as their own node in
        // the trace, making it clear at a glance where and how a human intervened on resume.
        observe:ResolveHumanApprovalSpan resolveSpan = observe:createResolveHumanApprovalSpan(sessionId);
        resolveSpan.addDecisions(from ApprovalRequest req in pendingApproval.pendingRequests
            where feedback.hasKey(req.id)
            select {id: req.id, toolName: req.toolName, decision: feedback.get(req.id).decision});
        resolveSpan.close();

        // Carry the original run's start time forward, so `Trace.startTime` reflects the
        // whole logical run rather than just this resume call.
        time:Utc startTime = pendingApproval.startTime;
        string executionId = pendingApproval.executionId;

        Credential? & readonly agentCredential = self.agentCredential;
        string? agentId = agentCredential is Credential ? agentCredential.id : ();
        // Re-derive the structured-output schema from the caller's `td` rather than persisting it
        // in the checkpoint. `td` is the authoritative return type on resume (it's what the final
        // answer binds to), and the instruction telling the model to use the tool is already in the
        // persisted history, so deriving here reproduces the same tool the original run exposed.
        ResponseSchema? responseSchema = ();
        if td !is typedesc<string|Trace> && td is typedesc<anydata> {
            ResponseSchema|Error schema = getResponseSchemaForType(td);
            if schema is Error {
                span.close(schema);
                return schema;
            }
            responseSchema = schema;
        }
        ExecutionTrace executionTrace = resumeRun(self, pendingApproval, feedback, self.maxIter,
            self.verbose, agentId, sessionId, context, responseSchema);
        // Safe: `isPendingApprovalHistoryValid` above already guarantees this index is in range.
        ChatUserMessage userMessage = <ChatUserMessage>pendingApproval.history[pendingApproval.historyPrefixLength - 1];
        return self.buildOutcome(executionId, userMessage, executionTrace, startTime, td, span, sessionId,
            "Agent execution paused again pending human approval",
            "Agent resume completed successfully",
            "Agent resume failed");
    }

    # Re-persists a `PendingApproval` claimed by `take()` when a resume call names an unknown
    # id before anything was actually resolved, so the caller can simply retry resume with a
    # corrected decision instead of losing the pause.
    #
    # + pendingApproval - The claimed pending approval to restore, unchanged
    # + sessionId - The ID associated with the agent memory
    private isolated function restoreClaimedApproval(PendingApproval pendingApproval, string sessionId) {
        Error? restoreErr = self.checkpointer.putCheckpoint(pendingApproval);
        if restoreErr is Error {
            log:printError("Failed to restore the claimed pending approval after an invalid resume call",
                    restoreErr, sessionId = sessionId);
        }
    }

    # Shared by both entry paths of `runInternal` (a fresh turn and a `Resume`): turns an
    # `ExecutionTrace` into the agent's public result - a pause passthrough, a successful answer
    # bound to `td`, or a failure - wrapped in a `Trace` when `td` is `Trace`, otherwise bound to
    # `td` (a `string`, or a concrete `anydata` type parsed from the structured answer).
    #
    # + executionId - Identifier of the logical execution this outcome belongs to
    # + userMessage - The turn's user message, for the returned `Trace`
    # + executionTrace - The trace produced by `run`/`resumeRun` for this call
    # + startTime - The logical run's start time, for the returned `Trace`
    # + td - Type descriptor specifying the expected return type format
    # + span - Observability span for this call, closed with the outcome
    # + sessionId - The ID associated with the agent memory
    # + pauseLogMessage - Message logged when the execution paused for human approval
    # + successLogMessage - Message logged when the execution completed successfully
    # + failedLogMessage - Message logged when the execution failed
    # + return - The agent's response bound to `td`, or an error
    private isolated function buildOutcome(string executionId, ChatUserMessage userMessage,
            ExecutionTrace executionTrace, time:Utc startTime, typedesc<Trace|anydata> td,
            observe:InvokeAgentSpan span, string sessionId, string pauseLogMessage, string successLogMessage,
            string failedLogMessage) returns Trace|anydata|Error {
        boolean withTrace = td is typedesc<Trace>;
        Iteration[] iterations = executionTrace.iterations;
        FunctionCall[]? toolCalls = executionTrace.toolCalls.length() == 0 ? () : executionTrace.toolCalls;

        Error? fatalError = executionTrace.fatalError;
        if fatalError is Error {
            log:printError(failedLogMessage, fatalError,
                    executionId = executionId,
                    agentId = self.agentId,
                    sessionId = sessionId
            );
            span.close(fatalError);
            // Mirror the withTrace wrapping used by the other failure branches, so a caller
            // requesting a `Trace` still gets the iteration/tool-call context on a fatal failure.
            return withTrace
                ? {
                    id: executionId,
                    userMessage,
                    iterations,
                    tools: self.toolSchemas,
                    startTime,
                    endTime: time:utcNow(),
                    output: fatalError,
                    toolCalls
                }
                : fatalError;
        }

        ApprovalRequiredError? pendingApproval = executionTrace.pendingApproval;
        if pendingApproval is ApprovalRequiredError {
            log:printDebug(pauseLogMessage,
                    executionId = executionId,
                    agentId = self.agentId,
                    sessionId = sessionId
            );
            // A pause for human approval is normal control flow, not a failure - closing the span
            // with the `ApprovalRequiredError` would mark it as errored and pollute error metrics.
            // Record what it paused on as a structured output and close the span successfully.
            ApprovalRequest[] requests = pendingApproval.detail().requests;
            span.addOutput(observe:JSON, {
                status: "approval_required",
                pendingCount: requests.length(),
                tools: from ApprovalRequest req in requests select req.toolName
            });
            // Emit a dedicated child span so the pause is visible as its own node in the trace,
            // making it clear at a glance where the run stopped to wait for a human.
            observe:RequestHumanApprovalSpan approvalSpan = observe:createRequestHumanApprovalSpan(sessionId);
            approvalSpan.addPendingCount(requests.length());
            approvalSpan.addRequests(from ApprovalRequest req in requests
                select {id: req.id, toolName: req.toolName, arguments: req.arguments, batchIndex: req.batchIndex});
            approvalSpan.close();
            span.close();
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

# Builds the dedicated final-answer tool that carries the structured-output schema as its parameters.
#
# + parameters - JSON schema describing the expected final-answer structure
# + return - The final-answer tool definition
isolated function getStructuredOutputTool(map<json> parameters) returns ChatCompletionFunctions => {
    name: STRUCTURED_OUTPUT_TOOL,
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
    "`" + STRUCTURED_OUTPUT_TOOL + "` tool with the answer provided as its arguments. " +
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

// `history` must contain, in order, a system message followed by a user message before the
// prefix ends (`run` always appends both - see `agent-utils.bal`), so a valid snapshot has
// `historyPrefixLength >= 2`. The prefix may equal `history.length()` when the very first tool
// call proposed is the one that paused, so `<=` (not `<`) is the correct upper bound.
isolated function isPendingApprovalHistoryValid(PendingApproval pendingApproval) returns boolean {
    ChatMessage[] history = pendingApproval.history;
    int historyPrefixLength = pendingApproval.historyPrefixLength;
    if historyPrefixLength < 2 || historyPrefixLength > history.length() {
        return false;
    }
    // Consumers unchecked-cast these two roles (see agent-utils.bal and the resume path here), so
    // this single check must also guarantee the roles, not just the bounds - otherwise a snapshot
    // from a custom store would panic instead of surfacing the "corrupted history" error.
    return history[0] is ChatSystemMessage && history[historyPrefixLength - 1] is ChatUserMessage;
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
