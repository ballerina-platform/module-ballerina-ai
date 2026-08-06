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

# Represents a short-term memory store that retains a fixed number of recent messages by a key,
# and persists human-in-the-loop pause checkpoints keyed by session ID.
#
# A store serves both concerns so one backend (e.g. a database or cache) durably holds the
# conversation history and the pause state together. `ShortTermMemory` delegates both its message
# operations and its checkpoint operations to the configured store, so a custom store that keeps
# messages durable also keeps human-in-the-loop pauses durable without any extra wiring. The
# built-in `InMemoryShortTermMemoryStore` keeps both in memory (not durable across a restart or a
# run on another replica).
public type ShortTermMemoryStore isolated object {

    # Retrieves the system message, if it was provided, for a given key.
    # 
    # + key - The key associated with the memory
    # + return - A copy of the message if it was specified, nil if it was not, or an 
    # `ai:MemoryError` error if the operation fails
    public isolated function getChatSystemMessage(string key) returns ChatSystemMessage|MemoryError?;

    # Retrieves all stored interactive chat messages (i.e., all chat messages except the system
    # message) for a given key.
    # 
    # + key - The key associated with the memory
    # + return - A copy of the messages, or an `ai:MemoryError` error if the operation fails
    public isolated function getChatInteractiveMessages(string key) returns ChatInteractiveMessage[]|MemoryError;

    # Retrieves all stored chat messages for a given key.
    # 
    # + key - The key associated with the memory
    # + return - A copy of the messages, or an `ai:MemoryError` error if the operation fails
    public isolated function getAll(string key) 
        returns [ChatSystemMessage, ChatInteractiveMessage...]|ChatInteractiveMessage[]|MemoryError;

    # Adds one or more chat messages to the memory store for a given key.
    #
    # + key - The key associated with the memory
    # + message - The chat message or array of messages to store
    # + return - nil on success, or an `ai:MemoryError` if the operation fails
    public isolated function put(string key, ChatMessage|ChatMessage[] message) returns MemoryError?;

    # Removes the system chat message, if specified, for a given key.
    # 
    # + key - The key associated with the memory
    # + return - nil on success or if there is no system chat message against the key, 
    #       or an `ai:MemoryError` error if the operation fails
    public isolated function removeChatSystemMessage(string key) returns MemoryError?;

    # Removes all stored interactive chat messages (i.e., all chat messages except the system
    # message) for a given key.
    # 
    # + key - The key associated with the memory
    # + count - Optional number of messages to remove, starting from the first interactive message in; 
    #               if not provided, removes all messages
    # + return - nil on success, or an `ai:MemoryError` error if the operation fails
    public isolated function removeChatInteractiveMessages(string key, int? count = ()) returns MemoryError?;

    # Removes all stored chat messages for a given key.
    # 
    # + key - The key associated with the memory
    # + return - nil on success, or an `ai:MemoryError` error if the operation fails
    public isolated function removeAll(string key) returns MemoryError?;

    # Checks if the memory store is full for a given key.
    # 
    # + key - The key associated with the memory
    # + return - true if the memory store is full, false otherwise, or an `ai:MemoryError` error if the operation fails
    public isolated function isFull(string key) returns boolean|MemoryError;

    # Returns the capacity configured for each key in the store.
    #
    # + return - returns the capacity
    public isolated function getCapacity() returns int;

    # Stores (or replaces) the pending human-in-the-loop approval for its session. Named
    # distinctly from the message operations so a single object (e.g. `ShortTermMemory`) can
    # expose both concerns without collision.
    #
    # + approval - The pending approval to persist
    # + return - `()` on success, or an `ai:Error` if the operation fails
    public isolated function putCheckpoint(PendingApproval approval) returns Error?;

    # Returns the pending human-in-the-loop approval for a session, if any.
    #
    # + sessionId - The session to look up
    # + return - The pending approval, `()` if none is pending, or an `ai:Error` if the operation fails
    public isolated function getCheckpoint(string sessionId) returns PendingApproval?|Error;

    # Removes the pending human-in-the-loop approval for a session, if any.
    #
    # + sessionId - The session to clear
    # + return - `()` on success, or an `ai:Error` if the operation fails
    public isolated function removeCheckpoint(string sessionId) returns Error?;

    # Atomically fetches and removes the pending human-in-the-loop approval for a session, if
    # any. Used to "claim" an approval before resolving it, so a concurrent duplicate resume
    # call for the same session cannot also claim and execute the same approved tool call.
    #
    # + sessionId - The session to claim
    # + return - The claimed pending approval, `()` if none was pending, or an `ai:Error` if the operation fails
    public isolated function takeCheckpoint(string sessionId) returns PendingApproval?|Error;
};

# Provides an in-memory chat message store.
public isolated class InMemoryShortTermMemoryStore {
    *ShortTermMemoryStore;

    private final int size;
    private final map<MemoryChatSystemMessage> systemMessages = {};
    private final map<MemoryChatInteractiveMessage[]> messages = {};
    // Human-in-the-loop pause checkpoints, keyed by session ID. Held in the isolated-safe stored
    // form (see `StoredPendingApproval`) so it can cross the `lock` boundary.
    private final map<StoredPendingApproval> pending = {};

    # Initializes a new in-memory store.
    # 
    # + size - The maximum capacity for stored messages
    public isolated function init(int size = 10) returns MemoryError? {
        if size < 3 {
            return error("Failed to initialize in-memory short term memory store: Size must be at least 3");
        }

        self.size = size;
    }

    # Retrieves the system message, if it was provided, for a given key.
    # 
    # + key - The key associated with the memory
    # + return - A copy of the message if it was specified, nil if it was not
    public isolated function getChatSystemMessage(string key) returns ChatSystemMessage? {
        lock {
            if self.systemMessages.hasKey(key) {
                return self.systemMessages.get(key);
            }
            return;
        }
    }

    # Retrieves a copy of all stored messages, with an optional system prompt.
    #
    # + key - The key associated with the memory
    # + return - A copy of the messages or an empty array if there are no messages yet
    public isolated function getChatInteractiveMessages(string key) returns ChatInteractiveMessage[] {
        lock {
            if self.messages.hasKey(key) {
                return self.messages.get(key).clone();
            }
            return [];
        }
    }

    # Retrieves all stored chat messages for a given key.
    # 
    # + key - The key associated with the memory
    # + return - A copy of the messages, or an `ai:MemoryError` error if the operation fails
    public isolated function getAll(string key) 
            returns [ChatSystemMessage, ChatInteractiveMessage...]|ChatInteractiveMessage[]|MemoryError {
        ChatSystemMessage? chatSystemMessage = self.getChatSystemMessage(key);
        if chatSystemMessage is MemoryChatSystemMessage {
            return [chatSystemMessage, ...self.getChatInteractiveMessages(key)];
        }
        return self.getChatInteractiveMessages(key);
    }

    # Adds one or more chat messages to the memory store for a given key.
    #
    # + key - The key associated with the memory
    # + message - The chat message or array of messages to store
    # + return - nil on success, or `ai:MemoryError` error if the operation fails 
    public isolated function put(string key, ChatMessage|ChatMessage[] message) returns MemoryError? {
        return message is ChatMessage
            ? self.putMessage(key, message)
            : message.forEach(msg => check self.putMessage(key, msg));
    }

    private isolated function putMessage(string key, ChatMessage message) returns MemoryError? {
        final readonly & MemoryChatMessage newMessage = check mapToMemoryChatMessage(message);
        lock {
            if newMessage is MemoryChatSystemMessage {
                self.systemMessages[key] = newMessage;
                return;
            }

            if !self.messages.hasKey(key) {
                self.messages[key] = [newMessage];
                return;
            }
            
            MemoryChatInteractiveMessage[] messages = self.messages.get(key);
            messages.push(newMessage);
        }
    }

    # Removes the system chat message, if specified, for a given key.
    # 
    # + key - The key associated with the memory
    public isolated function removeChatSystemMessage(string key) {
        lock {
            if self.systemMessages.hasKey(key) {
                _ = self.systemMessages.remove(key);
            }
        }
    }

    # Removes stored messages for a given key.
    # 
    # + key - The key associated with the memory
    # + count - Optional number of messages to remove, starting from the first non-system message in; 
    #               if not provided, removes all messages including the system message
    # + return - nil on success, or an `ai:MemoryError` error if the operation fails 
    public isolated function removeChatInteractiveMessages(string key, int? count = ()) returns MemoryError? {
        lock {
            // Handle invalid count values.
            if count is int && count <= 0 {
                return error("Count to remove must be nil or a positive integer.");
            }

            if !self.messages.hasKey(key) {
                return;
            }

            if count is () {
                self.messages.get(key).removeAll();
                return;
            }
            
            // If a count is provided, remove that many user messages from the start.
            MemoryChatMessage[] messages = self.messages.get(key);
            int countToRemove = count < messages.length() ? count : messages.length();

            foreach int index in 0 ..< countToRemove {
                _ = messages.shift();
            }
        }
    }

    # Removes all stored chat messages for a given key.
    # 
    # + key - The key associated with the memory
    # + return - nil on success, or an `ai:MemoryError` if the operation fails
    public isolated function removeAll(string key) returns MemoryError? {
        lock {
            if self.systemMessages.hasKey(key) {
                _ = self.systemMessages.remove(key);
            }

            if self.messages.hasKey(key) {
                self.messages.get(key).removeAll();
            }

            // Drop any pending approval checkpoint too, so clearing a session is atomic and an
            // abandoned pause does not retain its whole history snapshot indefinitely.
            if self.pending.hasKey(key) {
                _ = self.pending.remove(key);
            }
        }
    }

    # Checks if the memory store is full for a given key.
    # 
    # + key - The key associated with the memory
    # + return - true if the memory store is full, false otherwise
    public isolated function isFull(string key) returns boolean {
        lock {
            if !self.messages.hasKey(key) {
                return false;
            }

            return self.messages.get(key).length() == self.size;
        }
    }

    # Returns the capacity configured for each key in the `InMemoryShortTermMemoryStore`.
    #
    # + return - returns the capacity
    public isolated function getCapacity() returns int => self.size;

    # Stores (or replaces) the pending human-in-the-loop approval for its session.
    #
    # + approval - The pending approval to persist
    # + return - `()` on success, or an `ai:Error` if the operation fails
    public isolated function putCheckpoint(PendingApproval approval) returns Error? {
        StoredPendingApproval stored = check toStoredPendingApproval(approval);
        lock {
            self.pending[approval.sessionId] = stored.clone();
        }
    }

    # Returns the pending human-in-the-loop approval for a session, if any.
    #
    # + sessionId - The session to look up
    # + return - The pending approval, `()` if none is pending, or an `ai:Error` if the operation fails
    public isolated function getCheckpoint(string sessionId) returns PendingApproval?|Error {
        StoredPendingApproval? stored;
        lock {
            StoredPendingApproval? s = self.pending[sessionId];
            stored = s is () ? () : s.clone();
        }
        if stored is () {
            return ();
        }
        return fromStoredPendingApproval(stored);
    }

    # Removes the pending human-in-the-loop approval for a session, if any.
    #
    # + sessionId - The session to clear
    # + return - `()` on success, or an `ai:Error` if the operation fails
    public isolated function removeCheckpoint(string sessionId) returns Error? {
        lock {
            _ = self.pending.removeIfHasKey(sessionId);
        }
    }

    # Atomically fetches and removes the pending human-in-the-loop approval for a session, if any.
    #
    # + sessionId - The session to claim
    # + return - The claimed pending approval, `()` if none was pending, or an `ai:Error` if the operation fails
    public isolated function takeCheckpoint(string sessionId) returns PendingApproval?|Error {
        StoredPendingApproval? stored;
        lock {
            StoredPendingApproval? removed = self.pending.removeIfHasKey(sessionId);
            stored = removed is () ? () : removed.clone();
        }
        if stored is () {
            return ();
        }
        return fromStoredPendingApproval(stored);
    }
}
