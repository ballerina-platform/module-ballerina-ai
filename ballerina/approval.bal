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

import ballerina/log;
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
    # A JSON snapshot of the conversation history (a serialized `ChatMessage[]`),
    # used to continue reasoning on resume
    json history;
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

# Default in-memory implementation of `ApprovalStore`.
public isolated class InMemoryApprovalStore {
    *ApprovalStore;
    private final map<PendingApproval> pending = {};

    public isolated function put(PendingApproval approval) returns Error? {
        lock {
            self.pending[approval.sessionId] = approval.clone();
        }
    }

    public isolated function get(string sessionId) returns PendingApproval?|Error {
        lock {
            PendingApproval? approval = self.pending[sessionId];
            return approval.clone();
        }
    }

    public isolated function remove(string sessionId) returns Error? {
        lock {
            _ = self.pending.removeIfHasKey(sessionId);
        }
    }
}

# An `anydata`-safe representation of a `ChatMessage`, used to snapshot conversation
# history into a `PendingApproval`. `ChatMessage.content` can structurally be a `Prompt`
# (an object, not `anydata`), but the agent loop only ever constructs messages with plain
# `string` content, so this narrower shape is always sufficient in practice.
type StoredChatMessage record {|
    # Role of the message
    ROLE role;
    # Content of the message
    string? content = ();
    # An optional name for the participant
    string? name = ();
    # The function calls generated by the model, present for assistant messages
    FunctionCall[]? toolCalls = ();
    # Identifier for the tool call, present for function messages
    string? id = ();
|};

# Converts a conversation history snapshot into its `anydata`-safe stored form.
#
# + messages - The conversation history to convert
# + return - The stored representation of `messages`
isolated function toStoredMessages(ChatMessage[] messages) returns StoredChatMessage[] {
    StoredChatMessage[] stored = [];
    foreach ChatMessage msg in messages {
        if msg is ChatSystemMessage {
            string? name = msg?.name;
            stored.push({role: SYSTEM, content: toStoredContent(msg.content), name});
        } else if msg is ChatUserMessage {
            string? name = msg?.name;
            stored.push({role: USER, content: toStoredContent(msg.content), name});
        } else if msg is ChatAssistantMessage {
            string? name = msg?.name;
            stored.push({role: ASSISTANT, content: msg.content, toolCalls: msg.toolCalls, name});
        } else if msg is ChatFunctionMessage {
            string? id = msg?.id;
            stored.push({role: FUNCTION, content: msg.content, name: msg.name, id});
        }
    }
    return stored;
}

isolated function toStoredContent(string|Prompt content) returns string {
    if content is string {
        return content;
    }
    log:printWarn("A message with non-string content was captured across a human-in-the-loop pause; " +
            "its content will not survive the pause verbatim.");
    return "<non-string content>";
}

# Reconstructs a conversation history snapshot from its stored form.
#
# + stored - The stored messages to convert
# + return - The reconstructed conversation history
isolated function fromStoredMessages(StoredChatMessage[] stored) returns ChatMessage[] {
    ChatMessage[] messages = [];
    foreach StoredChatMessage s in stored {
        if s.role == SYSTEM {
            ChatSystemMessage sysMsg = {role: SYSTEM, content: s.content ?: ""};
            if s.name is string {
                sysMsg.name = s.name;
            }
            messages.push(sysMsg);
        } else if s.role == USER {
            ChatUserMessage userMsg = {role: USER, content: s.content ?: ""};
            if s.name is string {
                userMsg.name = s.name;
            }
            messages.push(userMsg);
        } else if s.role == ASSISTANT {
            ChatAssistantMessage assistantMsg = {role: ASSISTANT, content: s.content, toolCalls: s.toolCalls};
            if s.name is string {
                assistantMsg.name = s.name;
            }
            messages.push(assistantMsg);
        } else {
            ChatFunctionMessage functionMsg = {role: FUNCTION, content: s.content, name: s.name ?: ""};
            if s.id is string {
                functionMsg.id = s.id;
            }
            messages.push(functionMsg);
        }
    }
    return messages;
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
