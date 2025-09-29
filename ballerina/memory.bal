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

const string SUMMARY_PREFIX = "Summary of previous interactions:";
final readonly & string:RegExp chatHistoryRegex = re `\{\{CHAT_HISTORY\}\}`;
final readonly & string:RegExp maxSummaryTokenCountRegex = re `\{\{MAX_SUMMARY_TOKEN_COUNT\}\}`;

final readonly & Prompt DEFAULT_SUMMARY_PROMPT = `
    You are an expert at summarizing conversations.
    You will summarize a chat history between users and an AI agent to create a concise summary 
    that preserves the most important information while adhering to a specified token limit.

    Here is the chat history to summarize:

    <chat_history>
    {{CHAT_HISTORY}}
    </chat_history>

    Your summary must contain no more than {{MAX_SUMMARY_TOKEN_COUNT}} tokens.

    Before writing your summary, use the scratchpad below to plan your approach:

    <scratchpad>
    In this section, think through:
    - What are the main topics, questions, or issues discussed in the chat history?
    - What key information, decisions, or conclusions should be preserved?
    - What details can be omitted or condensed?
    - How can you structure the summary to be most useful for future reference?
    </scratchpad>

    When creating your summary, follow these guidelines:

    **What to prioritize:**
    - The most recent user request or question to ensure the summary reflects the immediate context.
    - Key questions asked and answers provided
    - Important decisions made or conclusions reached
    - Critical context that affects ongoing conversations
    - Unresolved issues that may need follow-up
    - Specific facts, numbers, or details that are likely to be referenced again

    **What to minimize or omit:**
    - Repetitive exchanges or clarifications
    - Casual conversation or pleasantries
    - Detailed explanations that can be inferred from context
    - Tangential discussions that don't affect the main topics

    **Structure your summary:**
    - Use clear, concise sentences
    - Group related topics together
    - Use bullet points or numbered lists when appropriate for clarity
    - Maintain chronological order when the sequence of events matters.

    Please do not include the scratchpad in your final summary.
    Please do not include any text before or after the summary.
`;

# Configuration for summarizing short-term memory content when it overflows.
public type OverflowSummarizationConfig record {|
    # AI model provider for generating summaries.
    ModelProvider modelProvider;
    # Prompt template for summarization.
    Prompt summarizationPrompt = DEFAULT_SUMMARY_PROMPT;
    # Maximum tokens for the summary output.
    int maxSummaryTokens = 1024;
|};

# Provides an in-memory chat message window with a limit on stored messages.
public isolated class MessageWindowChatMemory {
    *Memory;
    private final int size;
    private final map<MemoryChatMessage[]> sessions = {};
    private final map<MemoryChatSystemMessage> systemMessageSessions = {};
    private final OverflowSummarizationConfig? overflowSummarizationConfig;

    # Initializes a new memory window with a default or given size.
    # + size - The maximum capacity for stored messages
    # + summarizeOverflowConfig - Defines how content should be summarized when memory overflows.
    # If this is not provided, or if the configured size is less than 3 (too small),
    # the memory will discard the oldest messages instead of summarizing.
    public isolated function init(int size = 10, OverflowSummarizationConfig? overflowSummarizationConfig = ()) {
        self.size = size;
        if overflowSummarizationConfig is () {
            self.overflowSummarizationConfig = ();
            return;
        }

        Prompt summarizationPrompt = overflowSummarizationConfig.summarizationPrompt;
        self.overflowSummarizationConfig = {
            modelProvider: overflowSummarizationConfig.modelProvider,
            maxSummaryTokens: overflowSummarizationConfig.maxSummaryTokens,
            summarizationPrompt: createPrompt(
                    summarizationPrompt.strings,
                    summarizationPrompt.insertions.cloneReadOnly()
            )
        };
    }

    # Retrieves a copy of all stored messages, with an optional system prompt.
    #
    # + sessionId - The ID associated with the memory
    # + return - A copy of the messages, or an `ai:Error`
    public isolated function get(string sessionId) returns ChatMessage[]|MemoryError {
        lock {
            self.createSessionIfNotExist(sessionId);
            MemoryChatMessage[] memory = self.sessions.get(sessionId).clone();
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
        readonly & MemoryChatMessage newMessage = check self.mapToMemoryChatMessage(message);
        lock {
            self.createSessionIfNotExist(sessionId);

            if self.handleSystemMessage(sessionId, newMessage) {
                return;
            }

            self.manageMemoryOverflow(sessionId, newMessage.role);
            MemoryChatMessage[] memory = self.sessions.get(sessionId);
            memory.push(newMessage);
        }
    }

    isolated function mapToMemoryChatMessage(ChatMessage message) returns readonly & MemoryChatMessage|MemoryError {
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

    isolated function handleSystemMessage(string sessionId, readonly & MemoryChatMessage message) returns boolean {
        lock {
            if message is MemoryChatSystemMessage {
                self.systemMessageSessions[sessionId] = message;
                return true;
            }
            return false;
        }
    }

    isolated function manageMemoryOverflow(string sessionId, ROLE newMessageRole) {
        lock {
            MemoryChatMessage[] memory = self.sessions.get(sessionId);
            int size = self.size;

            if memory.length() >= size - 1 {
                OverflowSummarizationConfig? config = self.overflowSummarizationConfig;
                if config is () || size <= 3 {
                    trimOldestMessage(memory);
                } else {
                    summarizeAndRebuildMemory(memory, newMessageRole, config);
                }
            }
        }
    }
}

isolated function callSummarizationModel(ModelProvider provider, string prompt) returns ChatAssistantMessage|Error {
    return provider->chat({role: USER, content: `${prompt}`});
}

isolated function createPrompt(string[] & readonly strings, anydata[] & readonly insertions)
returns readonly & Prompt =>
    isolated object Prompt {
    public final string[] & readonly strings = strings;
    public final anydata[] & readonly insertions = insertions.cloneReadOnly();
};

isolated function stringifyPromptContent(Prompt prompt) returns string {
    string str = prompt.strings[0];
    anydata[] insertions = prompt.insertions;
    foreach int i in 0 ..< insertions.length() {
        str = str + insertions[i].toString() + prompt.strings[i + 1];
    }
    return str.trim();
}

isolated function summarizeAndRebuildMemory(MemoryChatMessage[] memory, ROLE newMessageRole, 
                OverflowSummarizationConfig config) {
    int memoryLength = memory.length();
    ROLE lastMessageRole = memory[memoryLength - 1].role;
    boolean isLastInteractionFromAgent = lastMessageRole != USER && newMessageRole == USER;

    MemoryChatMessage[] sliceToSummarize = isLastInteractionFromAgent
        ? memory.slice(0, memoryLength - 1)
        : memory;

    MemoryChatMessage|Error summaryMessage = generateSummary(
        sliceToSummarize, config.modelProvider, config.summarizationPrompt, config.maxSummaryTokens);

    if summaryMessage is Error {
        trimOldestMessage(memory);
        return;
    }

    if isLastInteractionFromAgent {
        MemoryChatMessage lastMessage = memory.pop();
        memory.removeAll();
        memory.push(lastMessage);
    } else {
        memory.removeAll();
    }
    memory.unshift(summaryMessage);
}

isolated function trimOldestMessage(MemoryChatMessage[] memory) {
    _ = memory.shift();
}

isolated function generateSummary(MemoryChatMessage[] slicedMemory, ModelProvider provider,
        Prompt summarizationPrompt, int maxSummaryTokens) returns MemoryChatMessage|Error {
    string updatedPrompt = chatHistoryRegex.replace(stringifyPromptContent(
            summarizationPrompt), slicedMemory.toString());
    updatedPrompt = maxSummaryTokenCountRegex.replace(updatedPrompt, maxSummaryTokens.toString());
    ChatAssistantMessage summarizationModelResult = check callSummarizationModel(provider, updatedPrompt);
    return {role: USER, content: string `${SUMMARY_PREFIX} ${summarizationModelResult.content.toString()}`};
}
