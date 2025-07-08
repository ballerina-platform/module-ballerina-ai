# Represents the memory interface for the agents.
public type Memory isolated object {

    # Retrieves all stored chat messages.
    #
    # + sessionId - The ID associated with the memory
    # + return - An array of messages or an `ai:Error`
    public isolated function get(string sessionId) returns ChatMessage[]|MemoryError;

    # Adds a chat message to the memory.
    #
    # + sessionId - The ID associated with the memory
    # + message - The message to store
    # + return - nil on success, or an `ai:Error` if the operation fails 
    public isolated function update(string sessionId, ChatMessage message) returns MemoryError?;

    # Deletes all stored messages.
    # + sessionId - The ID associated with the memory
    # + return - nil on success, or an `ai:Error` if the operation fails
    public isolated function delete(string sessionId) returns MemoryError?;
};

# Represents the parts of a prompt, including static string segments and dynamic insertions.
type PromptParts record {|
    # Read-only array of string literals from the template
    string[] & readonly strings;
    # Array of values to be inserted into the template, can be anydata, Document, or Chunk types
    (anydata|Document|Document[]|Chunk|Chunk[])[] insertions;
|};

type MemoryChatMessage MemoryChatUserMessage|MemoryChatSystemMessage|ChatAssistantMessage|ChatFunctionMessage;

type MemoryChatUserMessage readonly & record {|
    *ChatUserMessage;
|};

type MemoryChatSystemMessage readonly & record {|
    *ChatSystemMessage;
|};

# Provides an in-memory chat message window with a limit on stored messages.
public isolated class MessageWindowChatMemory {
    *Memory;
    private final int size;
    private final map<MemoryChatMessage[]> sessions = {};
    private final map<MemoryChatSystemMessage> systemMessageSessions = {};

    # Initializes a new memory window with a default or given size.
    # + size - The maximum capacity for stored messages
    public isolated function init(int size = 10) {
        self.size = size;
    }

    # Retrieves a copy of all stored messages, with an optional system prompt.
    #
    # + sessionId - The ID associated with the memory
    # + return - A copy of the messages, or an `ai:Error`
    public isolated function get(string sessionId) returns ChatMessage[]|MemoryError {
        lock {
            self.createSessionIfNotExist(sessionId);
            MemoryChatMessage[] memory = self.sessions.get(sessionId);
            if self.systemMessageSessions.hasKey(sessionId) {
                memory.unshift(self.systemMessageSessions.get(sessionId).clone());
            }
            return memory.clone();
        }
    }

    # Adds a message to the window.
    #
    # + sessionId - The ID associated with the memory
    # + message - The `ChatMessage` to store or use as system prompt
    # + return - nil on success, or an `ai:Error` if the operation fails 
    public isolated function update(string sessionId, ChatMessage message) returns MemoryError? {
        readonly & MemoryChatMessage newMessage = (check self.mapToMemoryChatMessage(message));
        lock {
            self.createSessionIfNotExist(sessionId);
            MemoryChatMessage[] memory = self.sessions.get(sessionId);
            if memory.length() >= self.size - 1 {
                _ = memory.shift();
            }
            if newMessage is MemoryChatSystemMessage {
                self.systemMessageSessions[sessionId] = newMessage;
                return;
            }
            memory.push(newMessage);
        }
    }

    private isolated function mapToMemoryChatMessage(ChatMessage message) returns readonly & MemoryChatMessage|MemoryError {
        if message is ChatAssistantMessage|ChatFunctionMessage {
            return message.cloneReadOnly();
        }
        final Prompt|string content = message.content;
        readonly & Prompt|string memoryContent;
        if content is Prompt {
            memoryContent = createPrompt(content.strings.cloneReadOnly(), content.insertions.cloneReadOnly());
        } else {
            memoryContent = content;
        }

        if message is ChatUserMessage {
            return {role: message.role, content: memoryContent, name: message.name};
        }
        if message is ChatSystemMessage {
            return {role: message.role, content: memoryContent, name: message.name};
        }
        return error MemoryError("Invalid message format found");
    }

    # Removes all messages from the memory.
    #
    # + sessionId - The ID associated with the memory
    # + return - nil on success, or an `ai:Error` if the operation fails 
    public isolated function delete(string sessionId) returns MemoryError? {
        lock {
            if !self.sessions.hasKey(sessionId) {
                return;
            }
            if self.systemMessageSessions.hasKey(sessionId) {
                _ = self.systemMessageSessions.remove(sessionId);
            }
            self.sessions.get(sessionId).removeAll();
        }
    }

    private isolated function createSessionIfNotExist(string sessionId) {
        lock {
            if !self.sessions.hasKey(sessionId) {
                self.sessions[sessionId] = [];
            }
        }
    }
}

isolated function createPrompt(string[] & readonly strings, anydata[] & readonly insertions) returns readonly & Prompt {
    return isolated object Prompt {
        public final string[] & readonly strings = strings;
        public final anydata[] & readonly insertions = insertions.cloneReadOnly();
    };
}
