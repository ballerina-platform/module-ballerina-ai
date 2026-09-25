// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
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

import ballerina/log;
import ballerina/time;

# An event emitted by a streamed agent run (`Agent.run` with `streaming = true`, bound to
# `stream<AgentEvent, Error?>`). A run yields any number of delta, tool-call and tool-result events,
# and ends with exactly one terminal event: `AgentCompletedEvent` or `ApprovalRequiredEvent`.
public type AgentEvent ContentDeltaEvent|ReasoningDeltaEvent|ToolCallEvent|ToolResultEvent
    |ApprovalRequiredEvent|AgentCompletedEvent;

# A fragment of the text the model is generating.
public type ContentDeltaEvent record {|
    # Discriminator identifying the event type
    "content_delta" kind = "content_delta";
    # The text fragment
    string content;
    # The reasoning-action cycle of the run this fragment belongs to
    int iteration;
|};

# A fragment of the model's reasoning/thinking, for models that expose it.
public type ReasoningDeltaEvent record {|
    # Discriminator identifying the event type
    "reasoning_delta" kind = "reasoning_delta";
    # The reasoning fragment
    string reasoning;
    # The reasoning-action cycle of the run this fragment belongs to
    int iteration;
|};

# A tool call proposed by the model, emitted once its streamed fragments have been fully assembled.
public type ToolCallEvent record {|
    # Discriminator identifying the event type
    "tool_call" kind = "tool_call";
    # Name of the tool
    string name;
    # Arguments the model proposed for the call
    map<json> arguments;
    # Identifier of the tool call, if the model provided one
    string id?;
    # The reasoning-action cycle of the run this call belongs to
    int iteration;
|};

# The outcome of a tool call: its output once executed, or the rejection if a human rejected it.
public type ToolResultEvent record {|
    # Discriminator identifying the event type
    "tool_result" kind = "tool_result";
    # Name of the tool
    string name;
    # The observation passed back to the model: the tool's output, or a description of the failure
    string output;
    # Whether the call failed
    boolean isError;
    # Identifier of the tool call, if the model provided one
    string id?;
    # The reasoning-action cycle of the run this result belongs to
    int iteration;
|};

# Terminal event: the run paused because one or more proposed tool calls require human approval.
# Continue it by passing a `Resume` with the decisions to `Agent.run`.
public type ApprovalRequiredEvent record {|
    # Discriminator identifying the event type
    "approval_required" kind = "approval_required";
    # Description of the pause
    string message;
    # The tool calls awaiting a decision
    ApprovalRequest[] requests;
|};

# Terminal event: the run completed with a final answer.
public type AgentCompletedEvent record {|
    # Discriminator identifying the event type
    "completed" kind = "completed";
    # The agent's final answer
    string answer;
|};

# Everything that precedes an agent's reasoning-action loop, prepared by `Agent.prepareExecution`
# and then either driven to completion (`Agent.run`) or one step at a time (a streamed run).
type PreparedExecution record {|
    # The loop to drive
    AgentLoop agentLoop;
    # Observability span for this call, closed with the outcome
    observe:InvokeAgentSpan span;
    # Identifier of the logical execution
    string executionId;
    # The ID associated with the agent memory
    string sessionId;
    # The turn's user message, for the returned `Trace`
    ChatUserMessage userMessage;
    # The logical run's start time
    time:Utc startTime;
    # For a resume, the pending approval claimed from the checkpointer
    PendingApproval? claimedApproval = ();
    # Message logged when the execution paused for human approval
    string pauseLogMessage;
    # Message logged when the execution completed successfully
    string successLogMessage;
    # Message logged when the execution failed
    string failedLogMessage;
|};

# Drives a prepared agent execution one step at a time as its event stream is consumed. Each call to
# `next` either pulls the next chunk of the model's streamed response (emitting its text and
# reasoning), or - once the response is complete - executes the proposed tool calls, or starts
# the next reasoning-action cycle. The loop state, human-in-the-loop handling and memory updates
# are shared with the non-streaming path through `AgentLoop`.
class AgentEventIterator {
    private final Agent agent;
    private final PreparedExecution execution;
    private AgentEvent[] pendingEvents = [];
    private stream<ChatMessageChunk, Error?>? chunks = ();
    private ChatMessageChunkAccumulator accumulator = new;
    # Set once the consumer first pulls from the stream, i.e. once the run may have had side effects
    private boolean started = false;
    # Set when the final answer was streamed as content deltas, rather than produced otherwise
    private boolean answerStreamed = false;
    private boolean done = false;
    private Error? terminalError = ();

    isolated function init(Agent agent, PreparedExecution execution) {
        self.agent = agent;
        self.execution = execution;
    }

    public isolated function next() returns record {|AgentEvent value;|}|Error? {
        while true {
            if self.pendingEvents.length() > 0 {
                return {value: self.pendingEvents.shift()};
            }
            if self.done {
                Error? err = self.terminalError;
                self.terminalError = ();
                return err;
            }
            self.started = true;
            stream<ChatMessageChunk, Error?>? chunks = self.chunks;
            if chunks is () {
                self.advance();
            } else {
                self.consumeChunk(chunks);
            }
        }
    }

    # Abandons the run if it has not completed: closes the model's stream and the span without
    # writing the turn to memory. A resume that has not started yet restores its claimed pending
    # approval, so it can still be resumed.
    #
    # + return - An error if closing the model's stream fails
    public isolated function close() returns Error? {
        if self.done {
            return;
        }
        self.done = true;
        self.pendingEvents = [];
        stream<ChatMessageChunk, Error?>? chunks = self.chunks;
        self.chunks = ();
        Error? closeErr = chunks is () ? () : chunks.close();
        PendingApproval? claimedApproval = self.execution.claimedApproval;
        if claimedApproval is PendingApproval && !self.started {
            self.agent.restoreClaimedApproval(claimedApproval, self.execution.sessionId);
        }
        log:printDebug("Agent event stream closed before the run completed",
                executionId = self.execution.executionId,
                sessionId = self.execution.sessionId
        );
        self.execution.span.close();
        return closeErr;
    }

    # Starts the next step of the loop: a pending resume step, the next reasoning-action cycle, or
    # the loop's conclusion.
    private isolated function advance() {
        Executor executor = self.execution.agentLoop.executor;
        if !executor.hasNext() {
            self.finish();
            return;
        }
        (ExecutionResult|ExecutionError)[]|BatchApprovalPending? seededStep = executor.takeSeededStep();
        if seededStep !is () {
            self.handleIterationResult(seededStep);
            return;
        }
        if !executor.startReasoningCycle() {
            self.finish();
            return;
        }
        stream<ChatMessageChunk, Error?>|Error chunks = executor.reasonAsStream();
        if chunks is Error {
            self.handleIterationResult(chunks);
            return;
        }
        self.chunks = chunks;
        self.accumulator = new;
    }

    # Pulls the next chunk of the model's response, or acts on the response once it is complete.
    #
    # + chunks - The model's chunk stream for the current reasoning-action cycle
    private isolated function consumeChunk(stream<ChatMessageChunk, Error?> chunks) {
        record {|ChatMessageChunk value;|}|Error? next = chunks.next();
        if next is record {|ChatMessageChunk value;|} {
            ChatMessageChunk chunk = next.value;
            self.accumulator.add(chunk);
            int iteration = self.execution.agentLoop.currentCycleNumber();
            string? reasoning = chunk.reasoning;
            if reasoning is string && reasoning.length() > 0 {
                ReasoningDeltaEvent event = {reasoning, iteration};
                self.pendingEvents.push(event);
            }
            string? content = chunk.content;
            if content is string && content.length() > 0 {
                ContentDeltaEvent event = {content, iteration};
                self.pendingEvents.push(event);
            }
            return;
        }
        self.chunks = ();
        if next is Error {
            Error? closeErr = chunks.close();
            if closeErr is Error {
                log:printDebug("Failed to close the model's stream after it failed", closeErr,
                        executionId = self.execution.executionId);
            }
            self.handleIterationResult(next);
            return;
        }

        Executor executor = self.execution.agentLoop.executor;
        ChatAssistantMessage|Error response = self.accumulator.toAssistantMessage();
        if response is Error {
            self.handleIterationResult(response);
            return;
        }
        FunctionCall[]|string|Error llmResponse = executor.interpretStreamedResponse(response);
        if llmResponse is Error {
            self.handleIterationResult(llmResponse);
            return;
        }
        if llmResponse is string {
            self.answerStreamed = true;
        } else {
            int iteration = self.execution.agentLoop.currentCycleNumber();
            foreach FunctionCall call in llmResponse {
                ToolCallEvent event = {name: call.name, arguments: call.arguments ?: {}, iteration};
                string? id = call.id;
                if id is string {
                    event.id = id;
                }
                self.pendingEvents.push(event);
            }
        }
        self.handleIterationResult(executor.act(llmResponse));
    }

    # Emits the tool results of a completed cycle and folds the cycle into the loop state.
    #
    # + result - The result of the reasoning-action cycle
    private isolated function handleIterationResult(IterationResult result) {
        if result is (ExecutionResult|ExecutionError)[] {
            int iteration = self.execution.agentLoop.currentCycleNumber();
            foreach ExecutionResult|ExecutionError step in result {
                self.pendingEvents.push(toToolResultEvent(step, iteration));
            }
        }
        if self.execution.agentLoop.processIteration(result) {
            self.finish();
        }
    }

    # Concludes the loop and emits its terminal event, or records the error that ends the stream.
    private isolated function finish() {
        self.done = true;
        AgentLoop agentLoop = self.execution.agentLoop;
        ExecutionTrace executionTrace = agentLoop.finish();
        Trace|anydata|Error outcome = self.agent.buildPreparedOutcome(self.execution, executionTrace, string);
        if outcome is ApprovalRequiredError {
            self.pendingEvents.push(toApprovalRequiredEvent(outcome));
        } else if outcome is Error {
            self.terminalError = outcome;
        } else if outcome is string {
            if !self.answerStreamed && outcome.length() > 0 {
                // The answer was not produced by the model's stream (e.g. an authorization failure
                // message), so emit it as content too - text-only consumers see only content deltas.
                ContentDeltaEvent event = {content: outcome, iteration: agentLoop.currentCycleNumber() - 1};
                self.pendingEvents.push(event);
            }
            AgentCompletedEvent event = {answer: outcome};
            self.pendingEvents.push(event);
        } else {
            self.terminalError = error Error("Unexpected outcome of the streamed agent execution.");
        }
    }
}

# Projects an agent event stream onto the answer text (`stream<string, Error?>`), yielding each
# content fragment. A pause for human approval ends the stream with an `ApprovalRequiredError`.
class AgentTextIterator {
    private final stream<AgentEvent, Error?> events;

    isolated function init(stream<AgentEvent, Error?> events) {
        self.events = events;
    }

    public isolated function next() returns record {|string value;|}|Error? {
        while true {
            record {|AgentEvent value;|}|Error? next = self.events.next();
            if next !is record {|AgentEvent value;|} {
                return next;
            }
            AgentEvent event = next.value;
            if event is ContentDeltaEvent {
                return {value: event.content};
            }
            if event is ApprovalRequiredEvent {
                return error ApprovalRequiredError(event.message, requests = event.requests);
            }
        }
    }

    public isolated function close() returns Error? {
        return self.events.close();
    }
}

# The fragments of one streamed tool call, accumulated across chunks by `index`.
type ToolCallFragments record {|
    # Index correlating the fragments of this tool call
    int index;
    # Identifier of the tool call
    string? id = ();
    # Name of the function to call
    string? name = ();
    # The concatenated JSON-string fragments of the function arguments
    string arguments = "";
|};

# Assembles the chunks of a streamed model response into a `ChatAssistantMessage`: concatenates
# the content and groups tool-call fragments by `index`, parsing each call's arguments once the
# response is complete.
class ChatMessageChunkAccumulator {
    private string content = "";
    private map<ToolCallFragments> toolCalls = {};
    private FinishReason? finishReason = ();

    isolated function add(ChatMessageChunk chunk) {
        string? content = chunk.content;
        if content is string {
            self.content += content;
        }
        ToolCallChunk[]? toolCallChunks = chunk.toolCalls;
        if toolCallChunks is ToolCallChunk[] {
            foreach ToolCallChunk fragment in toolCallChunks {
                string key = fragment.index.toString();
                ToolCallFragments toolCall = self.toolCalls[key] ?: {index: fragment.index};
                string? id = fragment?.id;
                if id is string {
                    toolCall.id = id;
                }
                string? name = fragment?.name;
                if name is string {
                    toolCall.name = name;
                }
                string? arguments = fragment?.arguments;
                if arguments is string {
                    toolCall.arguments += arguments;
                }
                self.toolCalls[key] = toolCall;
            }
        }
        FinishReason? finishReason = chunk.finishReason;
        if finishReason !is () {
            self.finishReason = finishReason;
        }
    }

    isolated function toAssistantMessage() returns ChatAssistantMessage|Error {
        ToolCallFragments[] fragments = from ToolCallFragments toolCall in self.toolCalls
            order by toolCall.index ascending
            select toolCall;
        if fragments.length() > 0 && self.finishReason == LENGTH {
            return error LlmInvalidGenerationError(
                "The model's response was truncated before its tool calls were complete.");
        }
        FunctionCall[] calls = [];
        foreach ToolCallFragments fragment in fragments {
            string? name = fragment.name;
            if name is () || name.length() == 0 {
                return error LlmInvalidGenerationError(
                    string `The streamed tool call at index ${fragment.index} has no function name.`);
            }
            FunctionCall call = {name, arguments: check parseToolCallArguments(name, fragment.arguments)};
            string? id = fragment.id;
            if id is string {
                call.id = id;
            }
            calls.push(call);
        }
        return {
            role: ASSISTANT,
            content: self.content.length() > 0 ? self.content : (),
            toolCalls: calls.length() > 0 ? calls : ()
        };
    }
}

isolated function parseToolCallArguments(string toolName, string rawArguments)
        returns map<json>|LlmInvalidGenerationError {
    string trimmed = rawArguments.trim();
    if trimmed.length() == 0 {
        return {};
    }
    json|error parsed = trimmed.fromJsonString();
    if parsed is map<json> {
        return parsed;
    }
    return error LlmInvalidGenerationError(
        string `Invalid or malformed arguments received in the streamed call to tool '${toolName}'.`,
        parsed is error ? parsed : ());
}

isolated function toToolResultEvent(ExecutionResult|ExecutionError step, int iteration) returns ToolResultEvent {
    if step is ExecutionResult {
        ToolResultEvent event = {
            name: step.tool.name,
            output: getObservationString(step.observation),
            isError: step.observation is error,
            iteration
        };
        string? id = step.tool.id;
        if id is string {
            event.id = id;
        }
        return event;
    }
    FunctionCall|error call = step.llmResponse.cloneWithType();
    ToolResultEvent event = {
        name: call is FunctionCall ? call.name : "",
        output: step.observation,
        isError: true,
        iteration
    };
    if call is FunctionCall {
        string? id = call.id;
        if id is string {
            event.id = id;
        }
    }
    return event;
}

isolated function toApprovalRequiredEvent(ApprovalRequiredError pause) returns ApprovalRequiredEvent => {
    message: pause.message(),
    requests: pause.detail().requests
};
