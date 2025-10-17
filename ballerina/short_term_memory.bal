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
public type OverflowTrimConfiguration record {|
    # Number of messages to trim when overflow occurs.
    int trimCount = 1;
|};

# Represents configuration to summarize messages when overflow occurs.
public type OverflowSummarizationConfiguration record {|
    # The model to use for summarization; if not provided, the default model is used.
    ModelProvider model?;
    # The prompt to use for summarization; if not provided, a default prompt is used.
    Prompt prompt = defaultSummarizationPrompt;
|};

# Represents configuration for handling overflow in short-term memory.
public type OverflowConfiguration OverflowTrimConfiguration|OverflowSummarizationConfiguration;

type OverflowHandler isolated function (
    ChatMessage[] messages, ROLE newMessageRole) returns ChatMessage[]|MemoryError;

type OverflowStrategy OverflowTrimConfiguration|OverflowHandler;

# Represents short-term memory for agents.
public isolated class ShortTermMemory {
    *Memory;

    private final OverflowStrategy overflowStrategy;
    // This should be final, but is not final intentionally, to enforce using locks.
    private ShortTermMemoryStore store;

    # Initializes short-term memory with an optional store and overflow configuration.
    # 
    # + store - The memory store to use; if not provided, an in-memory store is used
    # + overflowConfiguration - The strategy to handle overflow; if not provided, trimming is used
    # + return - nil on success, or an `ai:MemoryError` error if the initialization fails
    public isolated function init(ShortTermMemoryStore? store = (), 
                                  OverflowConfiguration overflowConfiguration = <OverflowTrimConfiguration> {}) 
                            returns MemoryError? {
        do {
            self.store = store ?: check new InMemoryShortTermMemoryStore();

            if overflowConfiguration is OverflowTrimConfiguration {
                self.overflowStrategy = overflowConfiguration.cloneReadOnly();
            } else {
                final ModelProvider model = overflowConfiguration.model ?: check getDefaultModelProvider();
                final Prompt prompt = overflowConfiguration.prompt;
                final string[] & readonly strings = prompt.strings;
                final anydata[] & readonly insertions = prompt.insertions.cloneReadOnly();
                self.overflowStrategy = isolated function (
                        ChatMessage[] messages, ROLE newMessageRole) returns ChatMessage[]|MemoryError {
                    return handleOverflow(model, createPrompt(strings, insertions), messages, newMessageRole);
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
            return self.store.get(key);
        }
    }

    # Adds a chat message to the memory, handling overflow as configured.
    #
    # + key - The key associated with the memory
    # + message - The message to store
    # + return - nil on success, or an `ai:MemoryError` error if the operation fails 
    public isolated function update(string key, ChatMessage message) returns MemoryError? {
        final string|([string[], anydata[]] & readonly)? content = let var messageContent = message.content in 
                messageContent is string ? messageContent : 
                    messageContent is () ? () :
                    [messageContent.strings, messageContent.insertions.cloneReadOnly()];
        lock {
            if self.store.isFull(key) {
                final OverflowStrategy overflowStrategy = self.overflowStrategy;

                if overflowStrategy is OverflowTrimConfiguration {
                    check self.store.remove(key, overflowStrategy.trimCount);
                } else {
                    ChatMessage[] updatedMessages = 
                        check overflowStrategy(check self.store.get(key), message.role);
                    check self.store.remove(key);
                    foreach ChatMessage updatedMessage in updatedMessages {
                        check self.store.put(key, updatedMessage);
                    }
                }
            }

            if message is ChatUserMessage {
                return self.store.put(key, <ChatUserMessage> {
                    role: USER, 
                    content: getPromptContent(<string|([string[], anydata[]] & readonly)> content),
                    name: message.name
                });
            }

            if message is ChatSystemMessage {
                return self.store.put(key, <ChatSystemMessage> {
                    role: SYSTEM,
                    content: getPromptContent(<string|([string[], anydata[]] & readonly)> content),
                    name: message.name
                });
            }

            if message is ChatAssistantMessage {
                return self.store.put(key, <ChatAssistantMessage> {
                    role: ASSISTANT,
                    content: <string?> content,
                    name: message.name,
                    toolCalls: message.toolCalls.clone()
                });
            }

            if message is ChatFunctionMessage {
                return self.store.put(key, <ChatFunctionMessage> {
                    role: FUNCTION,
                    content: <string?> content,
                    name: <string> message.name,
                    id: message.id
                });
            }

            panic error("Unexpected message type: " + (typeof message).toBalString());
        }
    }

    # Deletes all messages stored against a key.
    # 
    # + key - The key associated with the memory
    # + return - nil on success, or an `ai:MemoryError` error if the operation fails
    public isolated function delete(string key) returns MemoryError? {
        lock {
            return self.store.remove(key);
        }
    }
}

isolated function handleOverflow(
            ModelProvider model, Prompt & readonly prompt, ChatMessage[] memory, ROLE newMessageRole) 
        returns ChatMessage[]|MemoryError {
    int memoryLength = memory.length();
    if memoryLength == 0 {
        return [];
    }

    // Assumes a single system message at the start, if at all.
    // Not ideal, but since the interface does not expose system messages separately, no other option right now.
    ChatMessage firstMessage = memory[0];
    ChatSystemMessage? systemMessage = firstMessage is ChatSystemMessage ? firstMessage : ();

    int memoryLastIndex = memoryLength - 1;

    ChatMessage lastMessage = memory[memoryLastIndex];
    ROLE lastMessageRole = lastMessage.role;

    MemoryChatMessage[] memoryChatMessages = check mapToMemoryChatMessages(memory);
    boolean isLastMessageFromAI = lastMessageRole != USER && newMessageRole == USER;

    int startIndex = systemMessage is () ? 0 : 1;
    int endIndex = isLastMessageFromAI ? memoryLastIndex : memoryLength;

    MemoryChatMessage[] sliceToSummarize = startIndex != 0 || endIndex != memoryLength ? 
        memoryChatMessages.slice(startIndex, endIndex) : memoryChatMessages;

    MemoryChatMessage|Error summaryMessage = callModelToHandleOverflow(sliceToSummarize, model, prompt);
    if summaryMessage is Error {
        return error("Failed to generate summary: " + summaryMessage.message(), summaryMessage);
    }

    ChatMessage[] updatedMessages = [summaryMessage];
    if systemMessage is ChatSystemMessage {
        updatedMessages.unshift(systemMessage);
    }

    if isLastMessageFromAI {
        updatedMessages.push(lastMessage);
    }
    return updatedMessages;
}

isolated function callModelToHandleOverflow(MemoryChatMessage[] memorySlice, ModelProvider model, Prompt prompt) 
        returns MemoryChatMessage|Error {
    return model->chat({
        role: USER, 
        content: `${toString(prompt)} 
            
            The chat history to summarize: ${memorySlice.toString()}`
    });
}

isolated function toString(Prompt prompt) returns string {
    string[] & readonly strings = prompt.strings;
    anydata[] insertions = prompt.insertions;

    string promptString = strings[0];
    foreach int i in 0 ..< insertions.length() {
        promptString += insertions[i].toJsonString() + strings[i + 1];
    }
    return promptString;
}

isolated function getPromptContent(string|([string[], anydata[]] & readonly) content) returns string|Prompt => 
    content is string ? content : createPrompt(content[0], content[1]);
