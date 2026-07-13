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
    # The time at which the approval was requested
    time:Utc requestedAt;
    # The time at which the approval expires, if a timeout is configured
    time:Utc expiresAt?;
|};

# Approves the pending tool call, optionally replacing the proposed arguments.
public type Approval record {|
    # If set, the tool is executed with these arguments instead of the proposed ones
    map<json> arguments?;
    # Optional identifier of the approver, recorded for auditing
    string approver?;
|};

# Rejects the pending tool call. The tool is not executed; `feedback` is used
# to guide the agent's next step.
public type Rejection record {|
    # Guidance shown to the agent: why it was blocked, or what to do instead
    string feedback;
    # Optional identifier of the reviewer, recorded for auditing
    string approver?;
|};

# Represents a human's decision on a pending tool call.
public type HumanFeedback Approval|Rejection;

# The pending approval persisted across a pause, sufficient to resume the run
# without reloading conversation history from `Memory`.
public type PendingApproval record {|
    *ApprovalRequest;
    # Identifier of the original execution, carried through to the resumed `Trace`
    string executionId;
    # Number of iterations already consumed in this logical run
    int iterationsUsed;
    # A snapshot of the conversation history, used to continue reasoning on resume
    ChatMessage[] history;
    # Number of entries at the start of `history` that belong to memory loaded
    # prior to this turn (the system message, prior turns, and the user message)
    int historyPrefixLength;
|};

# Persists pending human approvals across a pause/resume, keyed by session ID.
public type ApprovalStore isolated object {
    # Stores (or replaces) the pending approval for its session.
    #
    # + approval - The pending approval to persist
    # + return - `()` on success, or an `ai:Error` if the operation fails
    public isolated function put(PendingApproval approval) returns Error?;

    # Returns the pending approval for a session, if any.
    #
    # + sessionId - The session to look up
    # + return - The pending approval, `()` if none is pending, or an `ai:Error` if the operation fails
    public isolated function get(string sessionId) returns PendingApproval?|Error;

    # Removes the pending approval for a session, if any.
    #
    # + sessionId - The session to clear
    # + return - `()` on success, or an `ai:Error` if the operation fails
    public isolated function remove(string sessionId) returns Error?;
};

# The pending approval as persisted internally by `InMemoryApprovalStore`: identical to
# `PendingApproval`, except `history` is the isolated-safe `MemoryChatMessage[]` (the same
# type `ShortTermMemoryStore`/`MessageWindowChatMemory` already use to store messages inside
# a `lock` block) rather than the plain `ChatMessage[]`, whose `Prompt`-typed content is not
# provably isolated. `MemoryChatMessage` is a subtype of `ChatMessage`, so converting back on
# `get` is a plain widening assignment; no separate reconstruction step is needed.
type StoredPendingApproval record {|
    *ApprovalRequest;
    # Identifier of the original execution, carried through to the resumed `Trace`
    string executionId;
    # Number of iterations already consumed in this logical run
    int iterationsUsed;
    # A snapshot of the conversation history, used to continue reasoning on resume
    MemoryChatMessage[] history;
    # Number of entries at the start of `history` that belong to memory loaded
    # prior to this turn (the system message, prior turns, and the user message)
    int historyPrefixLength;
|};

# Converts a conversation history snapshot into the isolated-safe form used for storage,
# reusing the same per-message conversion `Memory` implementations rely on.
#
# + messages - The conversation history to convert
# + return - The stored representation of `messages`, or an `ai:MemoryError` if a message
# could not be converted
isolated function toStoredHistory(ChatMessage[] messages) returns MemoryChatMessage[]|MemoryError =>
    from ChatMessage message in messages select check mapToMemoryChatMessage(message);

# Default in-memory implementation of `ApprovalStore`.
public isolated class InMemoryApprovalStore {
    *ApprovalStore;
    private final map<StoredPendingApproval> pending = {};

    public isolated function put(PendingApproval approval) returns Error? {
        MemoryChatMessage[]|MemoryError history = toStoredHistory(approval.history);
        if history is MemoryError {
            return history;
        }
        StoredPendingApproval stored = {
            id: approval.id,
            sessionId: approval.sessionId,
            toolName: approval.toolName,
            toolDescription: approval.toolDescription,
            arguments: approval.arguments,
            toolCallId: approval.toolCallId,
            requestedAt: approval.requestedAt,
            expiresAt: approval.expiresAt,
            executionId: approval.executionId,
            iterationsUsed: approval.iterationsUsed,
            history,
            historyPrefixLength: approval.historyPrefixLength
        };
        lock {
            self.pending[approval.sessionId] = stored.clone();
        }
    }

    public isolated function get(string sessionId) returns PendingApproval?|Error {
        lock {
            StoredPendingApproval? stored = self.pending[sessionId];
            return stored is () ? () : stored.clone();
        }
    }

    public isolated function remove(string sessionId) returns Error? {
        lock {
            _ = self.pending.removeIfHasKey(sessionId);
        }
    }
}

# Human-in-the-loop configuration for an agent.
public type ApprovalConfig record {|
    # Store used to persist pending approvals across pause/resume.
    # Defaults to an in-memory store.
    ApprovalStore store?;
    # Extra tools that require approval, addressed by name. Use this for
    # tools that cannot carry `@ai:AgentTool {requiresApproval: true}`,
    # such as tools discovered from a remote MCP server.
    string[] tools = [];
    # Seconds after which a pending approval expires. `()` means it never expires.
    decimal timeout?;
|};
