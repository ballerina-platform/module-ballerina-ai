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
    # Number of messages to trim when overflow occurs.
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

# Represents short-term memory for agents.
public isolated class ShortTermMemory {
    *Memory;

    private final OverflowHandler overflowHandler;
    // This should be final, but is not final intentionally, to enforce using locks.
    private ShortTermMemoryStore store;

    # Initializes short-term memory with an optional store and overflow configuration.
    # 
    # + store - The memory store to use; if not provided, an in-memory store is used
    # + overflowConfiguration - The strategy to handle overflow; if not provided, trimming is used
    # + return - nil on success, or an `ai:MemoryError` error if the initialization fails
    public isolated function init(ShortTermMemoryStore? store = (), 
                                  OverflowHandlerConfiguration overflowConfiguration = <TrimOverflowHandlerConfiguration> {}) 
                            returns MemoryError? {
        do {
            self.store = store ?: check new InMemoryShortTermMemoryStore();

            if overflowConfiguration is TrimOverflowHandlerConfiguration {
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

            if check self.exceedsMemoryLimit(key, memoryChatMessage) {
                final OverflowHandler overflowHandler = self.overflowHandler;
                if overflowHandler is TrimOverflowHandlerConfiguration {
                    check self.store.removeChatInteractiveMessages(key, overflowHandler.trimCount);
                    return self.store.put(key, memoryChatMessage);
                }
                ChatMessage[] updatedMessages = check overflowHandler(check self.store.getChatInteractiveMessages(key));
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
            MemoryChatMessage[] systemMessages = memoryChatMessages.filter(msg => msg is ChatSystemMessage);
            MemoryChatInteractiveMessage[] interactiveMessages = filterMemoryChatInteractiveMessage(memoryChatMessages);
            ChatMessage[] allMessages = [];
            if systemMessages.length() > 0 {
                // Update only the latest system message, ignore others
                MemoryChatSystemMessage lastSystemMessage = <MemoryChatSystemMessage>systemMessages.pop();
                allMessages = [lastSystemMessage];
            }

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
            int currentSize = (check self.store.getChatInteractiveMessages(key)).length();
            int maxSize = self.store.getCapacity();

            int incoming = message is ChatMessage ? 1 : message.length();
            return currentSize + incoming > maxSize;
        }
    }

    private isolated function getInteractiveMessagesAfterTrim(string key, TrimOverflowHandlerConfiguration trimHandler,
            MemoryChatInteractiveMessage[] incomingInteractiveMsgs) returns MemoryError|ChatMessage[] {
        lock {
            int incomingCount = incomingInteractiveMsgs.length();
            ChatMessage[] existing = check self.store.getChatInteractiveMessages(key);
            check self.store.removeChatInteractiveMessages(key);

            int currentSize = existing.length();
            int trimCount = trimHandler.trimCount;
            int capacity = self.store.getCapacity();

            // Count how many times trimming needs to occur during the simulation
            int totalMessages = currentSize + incomingCount;
            int trimCycles = totalMessages > capacity  ? ((totalMessages - capacity + trimCount - 1) / trimCount) : 0;
            int totalRemovals = trimCycles * trimCount;

            ChatMessage[] combined = [...existing, ...incomingInteractiveMsgs.clone()];
            combined = totalRemovals > 0 ? combined.slice(totalRemovals) : combined;
            return combined.'map(msg => check mapToMemoryChatMessage(msg)).clone();
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
}

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

isolated function toString(Prompt|string prompt) returns string {
    if prompt is string {
        return prompt;
    }
    string[] & readonly strings = prompt.strings;
    anydata[] insertions = prompt.insertions;

    string promptString = strings[0];
    foreach int i in 0 ..< insertions.length() {
        promptString += insertions[i].toJsonString() + strings[i + 1];
    }
    return promptString;
}

isolated function filterMemoryChatInteractiveMessage(MemoryChatMessage[] memoryChatMessages)
    returns MemoryChatInteractiveMessage[] => from MemoryChatMessage msg in memoryChatMessages
        where msg is MemoryChatInteractiveMessage
        select msg;
