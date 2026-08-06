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

import ballerina/time;

# A human-facing request to approve a proposed tool call.
public type ApprovalRequest record {|
    # Unique identifier for this approval request
    string id;
    # The ID associated with the agent memory for the paused run
    string sessionId;
    # Name of the tool the agent is proposing to call
    string toolName;
    # Description of the tool, as registered with the agent
    string toolDescription;
    # Arguments the agent is proposing to call the tool with
    map<json> arguments;
    # Identifier of the underlying tool call, used for message threading
    string toolCallId?;
    # Position of this call within the batch the LLM proposed in this turn. Used to apply a
    # resume decision back to the right call, and useful for display ("2 of 3 pending").
    int batchIndex;
|};

# A human reviewer's decision on a pending tool call. A call is either approved or rejected;
# editing the proposed arguments before approval is not supported.
public enum ApprovalDecision {
    APPROVE,
    REJECT
}

# Represents a human's decision on a pending tool call.
public type HumanResponse record {|
    # Whether the call is approved or rejected
    ApprovalDecision decision;
    # When rejecting, optional guidance shown to the agent: why it was blocked, or what to do instead
    string reason?;
|};

# Resumes a run that paused for human approval, carrying the human's decisions. Passed as the
# input to `Agent.run` (in place of a query) to continue a paused run rather than start a new one;
# `run` distinguishes the two by the input type. `decisions` is keyed by each request's
# `ApprovalRequest.id` - always a map, even for a single pending call, since a turn may propose
# several gated calls. A partial map (fewer entries than there are pending requests) is fine:
# whatever isn't supplied stays pending, and `run` returns a fresh `ApprovalRequiredError` listing
# just the still-undecided requests.
public type Resume record {|
    # The human's decisions on the pending tool calls, keyed by `ApprovalRequest.id`
    map<HumanResponse> decisions;
|};

# Determines whether a tool call requires human approval. `true`/`false` gates the tool
# unconditionally; a function decides per call from the proposed arguments.
#
# A function predicate is written with the **same parameter signature as the tool it gates** and
# returns `boolean`. The agent binds the proposed call's arguments to the predicate's parameters
# by name (exactly as it binds them to the tool), so a predicate for
# `isolated function issueRefund(string orderId, decimal amount)` is
# `isolated function (string orderId, decimal amount) returns boolean`. Only the tool's own
# (`anydata`) parameters are supported.
#
# The function runs synchronously, in-line with reasoning, and must be `isolated`. It must be
# deterministic given the proposed call's arguments. A function that panics (or whose result is
# not a `boolean`) fails safe: the call pauses for approval rather than executing unreviewed.
public type RequiresApproval boolean|isolated function;

# The pending approval persisted across a pause, sufficient to resume the run
# without reloading conversation history from `Memory`.
public type PendingApproval record {|
    # The session this pending approval belongs to
    string sessionId;
    # Identifier of the original execution, carried through to the resumed `Trace`
    string executionId;
    # Number of iterations already consumed in this logical run
    int iterationsUsed;
    # A snapshot of the conversation history, used to continue reasoning on resume
    ChatMessage[] history;
    # Number of entries at the start of `history` that belong to memory loaded
    # prior to this turn (the system message, prior turns, and the user message)
    int historyPrefixLength;
    # Iterations accumulated in this logical run prior to this pause, so that a `Trace`
    # produced after resuming reflects the whole run, not just the current call
    Iteration[] iterations;
    # Tool calls accumulated in this logical run prior to this pause
    FunctionCall[] toolCalls;
    # The original run's start time, carried unchanged across every subsequent pause
    time:Utc startTime;
    # The full batch of tool calls the LLM proposed in the turn that's currently gated
    FunctionCall[] originalBatch = [];
    # One request per gated position in `originalBatch` that still has no decision
    ApprovalRequest[] pendingRequests = [];
    # One slot per entry in `originalBatch`: `()` if not yet decided (or not gated at all),
    # otherwise the human's decision already gathered for that position
    HumanResponse?[] decisions = [];
|};

# The isolated-safe form of an `Iteration` used only by `InMemoryShortTermMemoryStore`'s
# checkpoint state. `history` is
# converted the same way as `PendingApproval.history` (see `StoredPendingApproval`). `output`
# narrows `Error` to a `string` summary: `Memory` faces this exact problem for tool
# observations already — by the time a result reaches `Memory`, any `error` has already been
# stringified into a `ChatFunctionMessage.content` (see `getObservationString` in
# `agent-utils.bal`), because Ballerina `error` values are never `Cloneable` and so can never
# cross a `lock` boundary. `Iteration.output` is the one place that still carries a raw `Error`
# (a reasoning/validation failure, not a tool result), so the same stringify-before-persist
# convention is applied here.
type StoredIteration record {|
    # History of chat messages up to this iteration, in the isolated-safe stored form
    MemoryChatMessage[] history;
    # Outputs produced by the agent in this iteration; an `Error` entry is stringified (see above)
    (ChatAssistantMessage|ChatFunctionMessage|string)[] output;
    # Start time of the iteration
    time:Utc startTime;
    # End time of the iteration
    time:Utc endTime;
|};

isolated function toStoredIterations(Iteration[] iterations) returns StoredIteration[]|MemoryError {
    StoredIteration[] stored = [];
    foreach Iteration iteration in iterations {
        MemoryChatMessage[]|MemoryError history = mapToMemoryChatMessages(iteration.history);
        if history is MemoryError {
            return history;
        }
        stored.push({
            history,
            output: toStoredOutputs(iteration.output),
            startTime: iteration.startTime,
            endTime: iteration.endTime
        });
    }
    return stored;
}

isolated function summarizeIterationError(Error err) returns string {
    error? cause = err.cause();
    return cause is error ? string `${err.message()} (cause: ${cause.message()})` : err.message();
}

# Ballerina query `select` clauses don't apply the same flow-typing as plain statements, so the
# per-element narrowing is done in a plain function (`toStoredOutput`/`fromStoredOutput`) and
# invoked here via a select clause that's just a function call, not an inline ternary.
#
# + output - A single iteration output to convert to its isolated-safe stored form
# + return - The stored form, with any `Error` stringified
isolated function toStoredOutput(ChatAssistantMessage|ChatFunctionMessage|Error output)
        returns ChatAssistantMessage|ChatFunctionMessage|string {
    if output is Error {
        return summarizeIterationError(output);
    }
    return output;
}

isolated function toStoredOutputs((ChatAssistantMessage|ChatFunctionMessage|Error)[] outputs)
        returns (ChatAssistantMessage|ChatFunctionMessage|string)[] =>
    from ChatAssistantMessage|ChatFunctionMessage|Error o in outputs select toStoredOutput(o);

isolated function fromStoredOutput(ChatAssistantMessage|ChatFunctionMessage|string stored)
        returns ChatAssistantMessage|ChatFunctionMessage|Error {
    if stored is string {
        return error Error(stored);
    }
    return stored;
}

isolated function fromStoredOutputs((ChatAssistantMessage|ChatFunctionMessage|string)[] stored)
        returns (ChatAssistantMessage|ChatFunctionMessage|Error)[] =>
    from ChatAssistantMessage|ChatFunctionMessage|string o in stored select fromStoredOutput(o);

isolated function fromStoredIterations(StoredIteration[] stored) returns Iteration[] =>
    from StoredIteration s in stored
    select fromStoredIteration(s);

isolated function fromStoredIteration(StoredIteration stored) returns Iteration =>
    {history: stored.history, output: fromStoredOutputs(stored.output), startTime: stored.startTime,
        endTime: stored.endTime};

# The pending approval as persisted internally by `InMemoryShortTermMemoryStore`: identical to
# `PendingApproval`, except `history` is the isolated-safe `MemoryChatMessage[]` (the same
# type `ShortTermMemoryStore`/`MessageWindowChatMemory` already use to store messages inside
# a `lock` block) rather than the plain `ChatMessage[]`, whose `Prompt`-typed content is not
# provably isolated, and `iterations` is `StoredIteration[]` for the same reason (see
# `StoredIteration`).
type StoredPendingApproval record {|
    # The session this pending approval belongs to
    string sessionId;
    # Identifier of the original execution, carried through to the resumed `Trace`
    string executionId;
    # Number of iterations already consumed in this logical run
    int iterationsUsed;
    # A snapshot of the conversation history, used to continue reasoning on resume
    MemoryChatMessage[] history;
    # Number of entries at the start of `history` that belong to memory loaded
    # prior to this turn (the system message, prior turns, and the user message)
    int historyPrefixLength;
    # Iterations accumulated in this logical run prior to this pause
    StoredIteration[] iterations;
    # Tool calls accumulated in this logical run prior to this pause
    FunctionCall[] toolCalls;
    # The original run's start time, carried unchanged across every subsequent pause
    time:Utc startTime;
    # The full batch of tool calls the LLM proposed in the turn that's currently gated
    FunctionCall[] originalBatch;
    # One request per gated position in `originalBatch` that still has no decision
    ApprovalRequest[] pendingRequests;
    # One slot per entry in `originalBatch`: `()` if not yet decided, otherwise the human's decision
    HumanResponse?[] decisions;
|};

# Converts a `PendingApproval` into its isolated-safe stored form for persistence inside a
# `lock` block (see `StoredPendingApproval`).
#
# + approval - The pending approval to convert
# + return - The stored form, or an `ai:MemoryError` if the history/iterations could not be converted
isolated function toStoredPendingApproval(PendingApproval approval) returns StoredPendingApproval|MemoryError {
    MemoryChatMessage[] history = check mapToMemoryChatMessages(approval.history);
    StoredIteration[] iterations = check toStoredIterations(approval.iterations);
    return {
        sessionId: approval.sessionId,
        executionId: approval.executionId,
        iterationsUsed: approval.iterationsUsed,
        history,
        historyPrefixLength: approval.historyPrefixLength,
        iterations,
        toolCalls: approval.toolCalls,
        startTime: approval.startTime,
        originalBatch: approval.originalBatch,
        pendingRequests: approval.pendingRequests,
        decisions: approval.decisions
    };
}

isolated function fromStoredPendingApproval(StoredPendingApproval stored) returns PendingApproval => {
    sessionId: stored.sessionId,
    executionId: stored.executionId,
    iterationsUsed: stored.iterationsUsed,
    history: stored.history,
    historyPrefixLength: stored.historyPrefixLength,
    iterations: fromStoredIterations(stored.iterations),
    toolCalls: stored.toolCalls,
    startTime: stored.startTime,
    originalBatch: stored.originalBatch,
    pendingRequests: stored.pendingRequests,
    decisions: stored.decisions
};
