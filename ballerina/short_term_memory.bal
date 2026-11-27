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

final readonly & Prompt defaultSummarizationPrompt = `
    You are an expert at summarizing conversations. You will summarize a chat history between a 
    user and an AI agent to create a concise summary that preserves the most important information.
    
    Before coming up with the summary, think through:
    - the main topics, questions, or issues discussed in the chat history
    - key information, decisions, or conclusions that should be preserved
    - what details can be omitted or condensed
    - how the summary can be structured to be useful for future reference

    Prioritize:
    - the most recent user request or question to ensure the summary reflects the immediate context
    - key decisions or conclusions reached during the conversation
    - critical context that affects ongoing conversations
    - unresolved issues that may need follow-up
    - specific details that are likely to be referenced again
    
    Expected structure:
    - Use clear, concise sentences
    - Group related topics together
    - Maintain chronological order when the sequence of events matters.`;

# Represents configuration to trim messages when overflow occurs.
public type TrimOverflowHandlerConfiguration record {|
    # Number of messages to trim when overflow occurs. Trimming may remove more or fewer messages to keep tool
    # results with their tool calls.
    int trimCount = 1;
|};

# Represents configuration to handle messages using a model when overflow occurs.
public type ModelAssistedOverflowHandlerConfiguration record {|
    # The model to use; if not provided, the default model is used.
    ModelProvider model?;
    # The prompt to use; if not provided, a default summarization prompt is used.
    Prompt prompt = defaultSummarizationPrompt;
|};

# Represents configuration for handling overflow in short-term memory.
public type OverflowHandlerConfiguration TrimOverflowHandlerConfiguration|ModelAssistedOverflowHandlerConfiguration;

type OverflowHandlerFunction isolated function (
        ChatInteractiveMessage[] messages) returns ChatInteractiveMessage[]|MemoryError;

type OverflowHandler TrimOverflowHandlerConfiguration|OverflowHandlerFunction;

# Represents short-term memory for agents. Persists both the conversation history and
# human-in-the-loop pause checkpoints in its configured `ShortTermMemoryStore`, so a single
# store durably serves both concerns.
public isolated class ShortTermMemory {
    *Memory;

    private final OverflowHandler overflowHandler;
    // Where both conversation messages and human-in-the-loop pause checkpoints live. `final`
    // because it is assigned once at init and never rebound; the message operations still take a
    // `lock` on `self` to keep their read-modify-write sequences atomic, while the checkpoint
    // operations delegate straight to the store, which does its own internal synchronization.
    private final ShortTermMemoryStore store;

    # Initializes short-term memory with an optional store and overflow configuration.
    #
    # + store - The memory store to use; if not provided, an in-memory store is used. The same
    # store persists both the conversation history and human-in-the-loop pause checkpoints, so a
    # store with a durable backend makes both durable.
    # + overflowConfiguration - The strategy to handle overflow; if not provided, trimming is used
    # + return - nil on success, or an `ai:MemoryError` error if the initialization fails
    public isolated function init(ShortTermMemoryStore? store = (),
                                  OverflowHandlerConfiguration overflowConfiguration = <TrimOverflowHandlerConfiguration> {})
                            returns MemoryError? {
        do {
            self.store = store ?: check new InMemoryShortTermMemoryStore();

            if overflowConfiguration is TrimOverflowHandlerConfiguration {
                if overflowConfiguration.trimCount <= 0 {
                    return error("trimCount must be a positive integer, found " +
                        overflowConfiguration.trimCount.toString());
                }
                self.overflowHandler = overflowConfiguration.cloneReadOnly();
            } else {
                final ModelProvider model = overflowConfiguration.model ?: check getDefaultModelProvider();
                final Prompt prompt = overflowConfiguration.prompt;
                final string[] & readonly strings = prompt.strings;
                final anydata[] & readonly insertions = prompt.insertions.cloneReadOnly();
                self.overflowHandler = isolated function (
                        ChatInteractiveMessage[] messages) returns ChatInteractiveMessage[]|MemoryError {
                    return handleOverflow(model, createPrompt(strings, insertions), messages);
                };
            }
        } on fail error e {
            return error("Failed to initialize short term memory: " + e.message(), e);
        }
    }

    # Retrieves all stored chat messages.
    #
    # + key - The key associated with the memory
    # + return - An array of messages or an `ai:MemoryError` error if the operation fails
    public isolated function get(string key) returns ChatMessage[]|MemoryError {
        lock {
            return self.store.getAll(key);
        }
    }

    # Adds one or more chat messages to the memory, handling overflow as configured.
    #
    # + key - The key associated with the memory
    # + message - The chat message or array of messages to store in memory
    # + return - nil on success, or an `ai:MemoryError` error if the operation fails 
    public isolated function update(string key, ChatMessage|ChatMessage[] message) returns MemoryError? {
        if message is ChatMessage[] {
            return self.batchUpdate(key, message);
        }
        final readonly & MemoryChatMessage memoryChatMessage = check mapToMemoryChatMessage(message);
        lock {
            if memoryChatMessage is ChatSystemMessage {
                return self.store.put(key, memoryChatMessage);
            }

            // Fetched once and used both to detect the overflow and to handle it, which saves a round trip
            // with a remote store.
            ChatInteractiveMessage[] existing = check self.store.getChatInteractiveMessages(key);
            if memoryChatMessage is ChatFunctionMessage
                    && !isToolCallOrResult(existing.length() > 0 ? existing[existing.length() - 1] : ()) {
                // A tool result whose tool call is not stored, for example because trimming removed it, is not kept.
                return;
            }
            int capacity = self.store.getCapacity();
            if existing.length() + 1 > capacity {
                final OverflowHandler overflowHandler = self.overflowHandler;
                if overflowHandler is TrimOverflowHandlerConfiguration {
                    int removals = getTrimmedCount([...existing, memoryChatMessage], overflowHandler.trimCount,
                        capacity);
                    int storedRemovals = int:min(removals, existing.length());
                    if storedRemovals > 0 {
                        check self.store.removeChatInteractiveMessages(key, storedRemovals);
                    }
                    if removals > existing.length() {
                        // The new message is a tool result whose tool call cannot be kept with it.
                        return;
                    }
                    return self.store.put(key, memoryChatMessage);
                }
                ChatMessage[] updatedMessages = check overflowHandler(existing);
                check self.store.removeChatInteractiveMessages(key);
                return self.store.put(key, [...updatedMessages, memoryChatMessage]);
            }
            return self.store.put(key, memoryChatMessage);
        }
    }

    private isolated function batchUpdate(string key, ChatMessage[] messages) returns MemoryError? {
        final readonly & MemoryChatMessage[] memoryChatMessages = from ChatMessage msg in messages
            select check mapToMemoryChatMessage(msg);
        lock {
            var [systemMessages, interactiveMessages] = partitionChatMessagesByType(memoryChatMessages);
            ChatMessage[] allMessages = [];
            if systemMessages.length() > 0 {
                // Update only the latest system message, ignore others
                allMessages = [systemMessages.pop()];
            }

            // Only a batch that starts with a tool result needs the stored messages, to check that its tool call
            // is stored; agents always start a batch with the user message.
            ChatInteractiveMessage? previous = ();
            if interactiveMessages.length() > 0 && interactiveMessages[0] is ChatFunctionMessage {
                ChatInteractiveMessage[] existing = check self.store.getChatInteractiveMessages(key);
                previous = existing.length() > 0 ? existing[existing.length() - 1] : ();
            }
            interactiveMessages = removeOrphanedToolResults(previous, interactiveMessages);

            if check self.exceedsMemoryLimit(key, interactiveMessages) {
                final OverflowHandler overflowHandler = self.overflowHandler;
                ChatMessage[] overflowHandledMessages = overflowHandler is TrimOverflowHandlerConfiguration
                    ? check self.getInteractiveMessagesAfterTrim(key, overflowHandler, interactiveMessages)
                    : check self.getInteractiveMessagesAfterSummarization(key, overflowHandler, interactiveMessages);
                allMessages.push(...overflowHandledMessages);
            } else {
                allMessages.push(...interactiveMessages);
            }
            
            if allMessages.length() == 0 {
                return;
            }
            return self.store.put(key, allMessages);
        }
    }

    private isolated function exceedsMemoryLimit(string key, ChatMessage|ChatMessage[] message)
        returns boolean|MemoryError {
        lock {
            int storeCapacity = self.store.getCapacity();
            int incomingMessageLength = message is ChatMessage ? 1 : message.length();
            // Early return to avoid a network-call/unnecessary store operation if incoming alone exceeds capacity
            if incomingMessageLength > storeCapacity {
                return true;
            }
            int currentLength = (check self.store.getChatInteractiveMessages(key)).length();
            return currentLength + incomingMessageLength > storeCapacity;
        }
    }

    private isolated function getInteractiveMessagesAfterTrim(string key, TrimOverflowHandlerConfiguration trimHandler,
            MemoryChatInteractiveMessage[] incomingInteractiveMsgs) returns MemoryError|ChatMessage[] {
        lock {
            int incomingCount = incomingInteractiveMsgs.length();
            ChatMessage[] existing = check self.store.getChatInteractiveMessages(key);

            int currentSize = existing.length();
            int trimCount = trimHandler.trimCount;
            int capacity = self.store.getCapacity();

            // Count how many times trimming needs to occur during the simulation
            int totalMessages = currentSize + incomingCount;
            int trimCycles = totalMessages > capacity  ? ((totalMessages - capacity + trimCount - 1) / trimCount) : 0;
            int totalRemovals = trimCycles * trimCount;

            ChatMessage[] combined = [...existing, ...incomingInteractiveMsgs.clone()];
            totalRemovals = getTrimmedCount(combined, totalRemovals, capacity);
            combined = totalRemovals > 0 ? combined.slice(totalRemovals) : combined;
            ChatMessage[] trimmed = combined.'map(msg => check mapToMemoryChatMessage(msg)).clone();
            check self.store.removeChatInteractiveMessages(key);
            return trimmed;
        }
    }

    private isolated function getInteractiveMessagesAfterSummarization(string key, OverflowHandlerFunction summarizationHandler,
            MemoryChatInteractiveMessage[] incomingInteractiveMsgs) returns MemoryError|ChatMessage[] {
        lock {
            MemoryChatInteractiveMessage[] interactiveMsgs = incomingInteractiveMsgs.clone();
            ChatInteractiveMessage[] currentMessages = check self.store.getChatInteractiveMessages(key);
            int incoming = interactiveMsgs.length();
            int maxSize = self.store.getCapacity();

            int effectiveCount = incoming % maxSize == 0 ? maxSize : incoming % maxSize;
            // The summary takes one message, or two when the last summarized message is a user message,
            // which is kept after the summary. Keep only as many incoming messages as fit alongside it, and
            // never start the kept messages with a tool result, which would separate it from its tool call.
            while effectiveCount > 0 {
                int headEnd = incoming - effectiveCount;
                if interactiveMsgs[headEnd] is ChatFunctionMessage {
                    effectiveCount -= 1;
                    continue;
                }
                ChatInteractiveMessage? lastSummarized = headEnd > 0 ? interactiveMsgs[headEnd - 1]
                    : currentMessages.length() > 0 ? currentMessages[currentMessages.length() - 1] : ();
                int summaryLength = lastSummarized is ChatUserMessage ? 2 : 1;
                if summaryLength + effectiveCount <= maxSize {
                    break;
                }
                effectiveCount -= 1;
            }
            ChatInteractiveMessage[] tailMessages = interactiveMsgs.slice(incoming - effectiveCount);

            ChatInteractiveMessage[] headMessages = interactiveMsgs.slice(0, incoming - effectiveCount);
            ChatMessage[] processedHead = check summarizationHandler([...currentMessages, ...headMessages]);

            check self.store.removeChatInteractiveMessages(key);
            ChatMessage[] combined = [...processedHead, ...tailMessages];
            return combined.'map(msg => check mapToMemoryChatMessage(msg)).clone();
        }
    }

    # Deletes all messages stored against a key.
    # 
    # + key - The key associated with the memory
    # + return - nil on success, or an `ai:MemoryError` error if the operation fails
    public isolated function delete(string key) returns MemoryError? {
        lock {
            return self.store.removeAll(key);
        }
    }

    # Stores (or replaces) the pending approval for its session.
    #
    # + approval - The pending approval to persist
    # + return - `()` on success, or an `ai:Error` if the operation fails
    public isolated function putCheckpoint(PendingApproval approval) returns Error? =>
        self.store.putCheckpoint(approval);

    # Returns the pending approval for a session, if any.
    #
    # + sessionId - The session to look up
    # + return - The pending approval, `()` if none is pending, or an `ai:Error` if the operation fails
    public isolated function getCheckpoint(string sessionId) returns PendingApproval?|Error =>
        self.store.getCheckpoint(sessionId);

    # Removes the pending approval for a session, if any.
    #
    # + sessionId - The session to clear
    # + return - `()` on success, or an `ai:Error` if the operation fails
    public isolated function removeCheckpoint(string sessionId) returns Error? =>
        self.store.removeCheckpoint(sessionId);

    # Atomically fetches and removes the pending approval for a session, if any.
    #
    # + sessionId - The session to claim
    # + return - The claimed pending approval, `()` if none was pending, or an `ai:Error` if the operation fails
    public isolated function takeCheckpoint(string sessionId) returns PendingApproval?|Error =>
        self.store.takeCheckpoint(sessionId);
}

// Returns how many of the oldest `messages` to remove, given that `removals` must be removed to fit the capacity.
// The kept messages never start with a tool result separated from its tool call: tool results at the start are
// removed as well, so trimming only ever removes more than `removals`, with one exception. The newest message is
// kept, even when `removals` exceeds the messages available, unless it is a tool result: then fewer messages are
// removed instead, keeping the assistant message with the tool call and its results, as long as they fit within the
// capacity. Otherwise, all messages are removed, since the tool result cannot be kept without its tool call.
isolated function getTrimmedCount(ChatMessage[] messages, int removals, int capacity) returns int {
    int lastIndex = messages.length() - 1;
    if lastIndex < 0 {
        return 0;
    }
    int firstKept = int:min(removals, lastIndex);
    while firstKept < lastIndex && messages[firstKept] is ChatFunctionMessage {
        firstKept += 1;
    }
    if messages[firstKept] !is ChatFunctionMessage {
        return firstKept;
    }
    int toolCallIndex = firstKept;
    while toolCallIndex > 0 && messages[toolCallIndex] is ChatFunctionMessage {
        toolCallIndex -= 1;
    }
    ChatMessage toolCallMessage = messages[toolCallIndex];
    if toolCallMessage is ChatAssistantMessage && (toolCallMessage.toolCalls ?: []).length() > 0
            && messages.length() - toolCallIndex <= capacity {
        return toolCallIndex;
    }
    return messages.length();
}

// Returns the incoming messages without the tool results that would be stored without their tool call. A tool
// result is kept only when the message before it, starting with `previous`, the last stored message, is an assistant
// message with tool calls or another kept tool result. Since the stored messages never hold such a tool result, this
// keeps it out of memory, for example when trimming removed its tool call.
isolated function removeOrphanedToolResults(ChatInteractiveMessage? previous,
        MemoryChatInteractiveMessage[] incoming) returns MemoryChatInteractiveMessage[] {
    MemoryChatInteractiveMessage[] kept = [];
    ChatInteractiveMessage? last = previous;
    foreach MemoryChatInteractiveMessage message in incoming {
        if message is ChatFunctionMessage && !isToolCallOrResult(last) {
            continue;
        }
        kept.push(message);
        last = message;
    }
    return kept;
}

isolated function isToolCallOrResult(ChatMessage? message) returns boolean =>
    message is ChatFunctionMessage || (message is ChatAssistantMessage && (message.toolCalls ?: []).length() > 0);

isolated function handleOverflow(
            ModelProvider model, Prompt & readonly prompt, ChatInteractiveMessage[] memory) 
        returns ChatInteractiveMessage[]|MemoryError {
    int memoryLength = memory.length();
    if memoryLength == 0 {
        return [];
    }

    int memoryLastIndex = memoryLength - 1;

    ChatInteractiveMessage lastMessage = memory[memoryLastIndex];

    MemoryChatInteractiveMessage[] memoryChatMessages = check mapToMemoryChatInteractiveMessages(memory);
    
    // Since we add the summary as an assistant message, we only summarize up to the last user message,
    // to maintain an interactive flow.
    boolean isLastMessageFromUser = lastMessage.role == USER;

    MemoryChatInteractiveMessage[] sliceToSummarize = isLastMessageFromUser ? 
        memoryChatMessages.slice(0, memoryLastIndex) : memoryChatMessages;

    ChatAssistantMessage|Error summaryMessage = callModelToHandleOverflow(sliceToSummarize, model, prompt);
    if summaryMessage is Error {
        return error("Failed to generate summary: " + summaryMessage.message(), summaryMessage);
    }

    ChatInteractiveMessage[] updatedMessages = [summaryMessage];
    if isLastMessageFromUser {
        updatedMessages.push(lastMessage);
    }
    return updatedMessages;
}

isolated function callModelToHandleOverflow(MemoryChatMessage[] memorySlice, ModelProvider model, Prompt prompt) 
        returns ChatAssistantMessage|Error {
    return model->chat([
        {
            role: SYSTEM,
            content: prompt
        },
        {
            role: USER, 
            content: `Summarize this chat history: ${memorySlice.toString()}`
        }
    ]);
}

isolated function toString(Prompt|anydata prompt) returns string {
    if prompt is anydata {
        return prompt.toString();
    }
    string[] & readonly strings = prompt.strings;
    anydata[] insertions = prompt.insertions;

    string promptString = strings[0];
    foreach int i in 0 ..< insertions.length() {
        promptString += insertions[i].toJsonString() + strings[i + 1];
    }
    return promptString;
}

isolated function partitionChatMessagesByType(MemoryChatMessage[] memoryChatMessages)
    returns [MemoryChatSystemMessage[], MemoryChatInteractiveMessage[]] {
    MemoryChatSystemMessage[] systemMessages = [];
    MemoryChatInteractiveMessage[] interactiveMessages = [];
    from MemoryChatMessage msg in memoryChatMessages
    do {
        if msg is MemoryChatSystemMessage {
            systemMessages.push(msg);
        } else {
            interactiveMessages.push(msg);
        }
    };
    return [systemMessages, interactiveMessages];
}
