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

import ballerina/test;

const string K1 = "key1";
const string K2 = "key2";

const ChatSystemMessage K1SM1 = {role: SYSTEM, content: "You are a helpful assistant that is aware of the weather."};

const ChatUserMessage K1M1 = {role: USER, content: "Hello, my name is Alice. I'm from Seattle."};
final readonly & ChatAssistantMessage k1m2 = {role: ASSISTANT, content: "Hello Alice, what can I do for you?"};
const ChatUserMessage K1M3 = {role: USER, content: "I would like to know the weather today."};
final readonly & ChatAssistantMessage K1M4 = {role: ASSISTANT, 
        content: "The weather in Seattle today is mostly cloudy with occasional showers and a high around 58°F."};

const ChatUserMessage K2M1 = {role: USER, content: "Hello, my name is Bob."};

@test:Config
function testBasicShortTermMemory() returns error? {
    Memory memory = check new ShortTermMemory();

    check memory.update(K1, K1SM1);
    check memory.update(K1, K1M1);
    check memory.update(K2, K2M1);

    ChatMessage[] k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 2);
    assertChatMessageEquals(k1CurrentMemory[0], K1SM1);
    assertChatMessageEquals(k1CurrentMemory[1], K1M1);

    ChatMessage[] k2CurrentMemory = check memory.get(K2);
    test:assertEquals(k2CurrentMemory.length(), 1);
    assertChatMessageEquals(k2CurrentMemory[0], K2M1);

    // Check removal of all messages for a key.
    check memory.delete(K1);
    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 0);

    k2CurrentMemory = check memory.get(K2);
    test:assertEquals(k2CurrentMemory.length(), 1);
    assertChatMessageEquals(k2CurrentMemory[0], K2M1);

    // Add more messages to K1 after deletion.
    check memory.update(K1, k1m2);
    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 1);
    assertChatMessageEquals(k1CurrentMemory[0], k1m2);
}

@test:Config
function testShortTermMemoryWithInMemoryStoreTrimmingOnOverflow() returns error? {
    InMemoryShortTermMemoryStore store = check new (3);
    Memory memory = check new ShortTermMemory(store);

    check memory.update(K1, K1SM1);
    check memory.update(K1, K1M1);

    ChatMessage[] k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 2);
    assertChatMessageEquals(k1CurrentMemory[0], K1SM1);
    assertChatMessageEquals(k1CurrentMemory[1], K1M1);

    check memory.update(K1, k1m2);
    check memory.update(K1, K1M3);
    check memory.update(K2, K2M1);

    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 4);
    assertChatMessageEquals(k1CurrentMemory[0], K1SM1);
    assertChatMessageEquals(k1CurrentMemory[1], K1M1);
    assertChatMessageEquals(k1CurrentMemory[2], k1m2);
    assertChatMessageEquals(k1CurrentMemory[3], K1M3);

    // Overflows here
    check memory.update(K1, K1M4);

    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 4);
    assertChatMessageEquals(k1CurrentMemory[0], K1SM1);
    assertChatMessageEquals(k1CurrentMemory[1], k1m2);
    assertChatMessageEquals(k1CurrentMemory[2], K1M3);
    assertChatMessageEquals(k1CurrentMemory[3], K1M4);

    ChatMessage[] k2CurrentMemory = check memory.get(K2);
    test:assertEquals(k2CurrentMemory.length(), 1);
    assertChatMessageEquals(k2CurrentMemory[0], K2M1);
}

@test:Config
function testShortTermMemoryWithInMemoryStoreTrimmingOnOverflowWithBatchUpdate() returns error? {
    InMemoryShortTermMemoryStore store = check new (3);
    Memory memory = check new ShortTermMemory(store);

    check memory.update(K1, [K1SM1, K1M1]);

    ChatMessage[] k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 2);
    assertChatMessageEquals(k1CurrentMemory[0], K1SM1);
    assertChatMessageEquals(k1CurrentMemory[1], K1M1);

    check memory.update(K1, [k1m2, K1M3]);
    check memory.update(K2, K2M1);

    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 4);
    assertChatMessageEquals(k1CurrentMemory[0], K1SM1);
    assertChatMessageEquals(k1CurrentMemory[1], K1M1);
    assertChatMessageEquals(k1CurrentMemory[2], k1m2);
    assertChatMessageEquals(k1CurrentMemory[3], K1M3);

    // Overflows here
    check memory.update(K1, [K1M4, K1M1, k1m2]);

    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 4);
    assertChatMessageEquals(k1CurrentMemory[0], K1SM1);
    assertChatMessageEquals(k1CurrentMemory[1], K1M4);
    assertChatMessageEquals(k1CurrentMemory[2], K1M1);
    assertChatMessageEquals(k1CurrentMemory[3], k1m2);

    ChatMessage[] k2CurrentMemory = check memory.get(K2);
    test:assertEquals(k2CurrentMemory.length(), 1);
    assertChatMessageEquals(k2CurrentMemory[0], K2M1);
}

@test:Config
function testShortTermMemoryWithInMemoryStoreCustomTrimmingOnOverflow() returns error? {
    InMemoryShortTermMemoryStore store = check new (3);
    Memory memory = check new ShortTermMemory(store, <TrimOverflowHandlerConfiguration>{trimCount: 3});

    check memory.update(K1, K1M1);
    check memory.update(K1, k1m2);
    check memory.update(K1, K1M3);

    ChatMessage[] k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 3);
    assertChatMessageEquals(k1CurrentMemory[0], K1M1);
    assertChatMessageEquals(k1CurrentMemory[1], k1m2);
    assertChatMessageEquals(k1CurrentMemory[2], K1M3);

    // Overflows here
    check memory.update(K1, K1M4);

    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 1);
    assertChatMessageEquals(k1CurrentMemory[0], K1M4);
}

@test:Config
function testShortTermMemoryWithInMemoryStoreCustomTrimmingOnOverflowWithBatchUpdate() returns error? {
    InMemoryShortTermMemoryStore store = check new (3);
    Memory memory = check new ShortTermMemory(store, <TrimOverflowHandlerConfiguration>{trimCount: 3});

    check memory.update(K1, [K1M1, k1m2, K1M3]);

    ChatMessage[] k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 3);
    assertChatMessageEquals(k1CurrentMemory[0], K1M1);
    assertChatMessageEquals(k1CurrentMemory[1], k1m2);
    assertChatMessageEquals(k1CurrentMemory[2], K1M3);

    // Overflows here
    check memory.update(K1, [K1M4, K1M1]);

    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 2);
    assertChatMessageEquals(k1CurrentMemory[0], K1M4);
    assertChatMessageEquals(k1CurrentMemory[1], K1M1);
}

@test:Config
function testShortTermMemoryWithInCommingBatchSizeLargerThanCapacity() returns error? {
    InMemoryShortTermMemoryStore store = check new (3);
    Memory memory = check new ShortTermMemory(store, <TrimOverflowHandlerConfiguration>{trimCount: 3});

    check memory.update(K1, [K1M1, k1m2, K1M3, K1M4]);
    ChatMessage[] k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 1);
    assertChatMessageEquals(k1CurrentMemory[0], K1M4);
}

const CHAT_METHOD = "chat";

@test:Config
function testShortTermMemoryWithSummarizationOnOverflow1() returns error? {
    final readonly & ChatAssistantMessage memorySummaryMessage = {
        role: ASSISTANT,
        content: string `The user inquired about their tasks for the day. The AI assistant retrieved and 
            listed the user's tasks, which are:

            1. **Buy groceries** - Completed
            2. **Finish the project report** - Due by October 20, 2025
            3. **Call Alice** - Due by October 21, 2025

            The assistant offered further assistance if needed.`
    };

    final readonly & ChatSystemMessage ksm1 = {
        role: SYSTEM, 
        content: string `
            # Role  
            Task Assistant  

            # Instructions  
            You are a helpful assistant that guides users with their todo lists.`
    };

    final readonly & ChatUserMessage km1 = {
        role: USER, 
        content: "Hello, what do I have on my plate today?"
    };

    final readonly & ChatAssistantMessage km2 = {
        role: ASSISTANT,
        toolCalls: [
            {
                name: "listTasks",
                arguments: {}
            }
        ]
    };

    final readonly & ChatFunctionMessage km3 = {
        role: FUNCTION,
        name: "listTasks",
        content: "[{\"description\":\"Buy groceries\",\"dueBy\":\"2025-10-19\",\"completed\":true}," +
            "{\"description\":\"Finish the project report\",\"dueBy\":\"2025-10-20\",\"completed\":false}," +
            "{\"description\":\"Call Alice\",\"dueBy\":\"2025-10-21\",\"completed\":false}]"
    };

    final readonly & ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: string `
            Today, you have the following task on your plate:

            1. **Finish the project report** - Due by **October 20, 2025**.

            Let me know if you need help with anything!`
    };

    InMemoryShortTermMemoryStore store = check new (4);
    ModelProvider model = isolated client object {
        isolated remote function chat(
                ChatMessage[]|ChatUserMessage messages, 
                ChatCompletionFunctions[] tools, string? stop) returns ChatAssistantMessage|Error {
            assertSummarizationRequestChatMessages(messages, [km1, km2, km3, km4], defaultSummarizationPrompt);
            return memorySummaryMessage;                    
        }

        isolated remote function generate(Prompt prompt, typedesc<anydata> td) returns td|Error = external;
    };

    Memory memory = check new ShortTermMemory(
        store,
        overflowConfiguration = {
            model
        }
    );
    
    final string k = "key";

    check memory.update(k, ksm1);
    check memory.update(k, km1);
    check memory.update(k, km2);
    check memory.update(k, km3);
    check memory.update(k, km4);

    ChatMessage[] k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 5);
    assertChatMessageEquals(k3CurrentMemory[0], ksm1);
    assertChatMessageEquals(k3CurrentMemory[1], km1);
    assertChatMessageEquals(k3CurrentMemory[2], km2);
    assertChatMessageEquals(k3CurrentMemory[3], km3);
    assertChatMessageEquals(k3CurrentMemory[4], km4);

    final readonly & ChatUserMessage km5 = {
        role: USER,
        content: "What about tomorrow?"
    };
    check memory.update(k, km5);

    k3CurrentMemory = check memory.get(k);    
    test:assertEquals(k3CurrentMemory.length(), 3);
    assertChatMessageEquals(k3CurrentMemory[0], ksm1);
    assertChatMessageEquals(k3CurrentMemory[1], memorySummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[2], km5);
}

@test:Config
function testShortTermMemoryWithSummarizationOnOverflow1WithBatchUpdate() returns error? {
    final readonly & ChatAssistantMessage memorySummaryMessage = {
        role: ASSISTANT,
        content: string `The user inquired about their tasks for the day. The AI assistant retrieved and 
            listed the user's tasks, which are:

            1. **Buy groceries** - Completed
            2. **Finish the project report** - Due by October 20, 2025
            3. **Call Alice** - Due by October 21, 2025

            The assistant offered further assistance if needed.`
    };

    final readonly & ChatSystemMessage ksm1 = {
        role: SYSTEM,
        content: string `
            # Role  
            Task Assistant  

            # Instructions  
            You are a helpful assistant that guides users with their todo lists.`
    };

    final readonly & ChatUserMessage km1 = {
        role: USER,
        content: "Hello, what do I have on my plate today?"
    };

    final readonly & ChatAssistantMessage km2 = {
        role: ASSISTANT,
        toolCalls: [
            {
                name: "listTasks",
                arguments: {}
            }
        ]
    };

    final readonly & ChatFunctionMessage km3 = {
        role: FUNCTION,
        name: "listTasks",
        content: "[{\"description\":\"Buy groceries\",\"dueBy\":\"2025-10-19\",\"completed\":true}," +
            "{\"description\":\"Finish the project report\",\"dueBy\":\"2025-10-20\",\"completed\":false}," +
            "{\"description\":\"Call Alice\",\"dueBy\":\"2025-10-21\",\"completed\":false}]"
    };

    final readonly & ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: string `
            Today, you have the following task on your plate:

            1. **Finish the project report** - Due by **October 20, 2025**.

            Let me know if you need help with anything!`
    };

    InMemoryShortTermMemoryStore store = check new (4);
    ModelProvider model = isolated client object {
        isolated remote function chat(
                ChatMessage[]|ChatUserMessage messages,
                ChatCompletionFunctions[] tools, string? stop) returns ChatAssistantMessage|Error {
            assertSummarizationRequestChatMessages(messages, [km1, km2, km3, km4], defaultSummarizationPrompt);
            return memorySummaryMessage;
        }

        isolated remote function generate(Prompt prompt, typedesc<anydata> td) returns td|Error = external;
    };

    Memory memory = check new ShortTermMemory(
        store,
        overflowConfiguration = {
            model
        }
    );

    final string k = "key";

    ChatMessage[] k3CurrentMemory = check memory.get(k);

    final readonly & ChatUserMessage km5 = {
        role: USER,
        content: "What about tomorrow?"
    };
    check memory.update(k, [ksm1, km1, km2, km3, km4, km5]);

    k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 3);
    assertChatMessageEquals(k3CurrentMemory[0], ksm1);
    assertChatMessageEquals(k3CurrentMemory[1], memorySummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[2], km5);
}

@test:Config
function testShortTermMemoryWithSummarizationOnOverflow2() returns error? {
    final readonly & ChatAssistantMessage memorySummaryMessage = {
        role: ASSISTANT,
        content: string `"**Summary of Chat History:**
                1. **User Inquiry:** The user asked the AI about their tasks for the day.
                
                2. **AI Response:** The AI checked the user's task list.

                3. **Tasks Listed:**
                - **Completed Tasks:**
                    - Buy groceries (due by 2025-10-19)
                - **Pending Tasks:**
                    - Finish the project report (due by 2025-10-20)
                    - Call Alice (due by 2025-10-21)`
    };

    Memory memory = check new ShortTermMemory(
        check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {
            model: new MockSummarizerModel(memorySummaryMessage)
        }
    );
    
    final string k = "key";

    final readonly & ChatUserMessage km1 = {
        role: USER, 
        content: "Hello, what do I have on my plate today?"
    };
    check memory.update(k, km1);

    final readonly & ChatAssistantMessage km2 = {
        role: ASSISTANT,
        toolCalls: [
            {
                name: "listTasks",
                arguments: {}
            }
        ]
    };
    check memory.update(k, km2);

    final readonly & ChatFunctionMessage km3 = {
        role: FUNCTION,
        name: "listTasks",
        content: "[{\"description\":\"Buy groceries\",\"dueBy\":\"2025-10-19\",\"completed\":true}," +
            "{\"description\":\"Finish the project report\",\"dueBy\":\"2025-10-20\",\"completed\":false}," +
            "{\"description\":\"Call Alice\",\"dueBy\":\"2025-10-21\",\"completed\":false}]"
    };
    check memory.update(k, km3);

    ChatMessage[] k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 3);
    assertChatMessageEquals(k3CurrentMemory[0], km1);
    assertChatMessageEquals(k3CurrentMemory[1], km2);
    assertChatMessageEquals(k3CurrentMemory[2], km3);

    final readonly & ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: string `
            Today, you have the following task on your plate:

            1. **Finish the project report** - Due by **October 20, 2025**.

            Let me know if you need help with anything!`
    };
    check memory.update(k, km4);

    k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 2);
    assertChatMessageEquals(k3CurrentMemory[0], memorySummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[1], km4);
}

@test:Config
function testShortTermMemoryWithSummarizationOnOverflow2OnBatchUpdate() returns error? {
    final readonly & ChatAssistantMessage memorySummaryMessage = {
        role: ASSISTANT,
        content: string `"**Summary of Chat History:**
                1. **User Inquiry:** The user asked the AI about their tasks for the day.
                
                2. **AI Response:** The AI checked the user's task list.

                3. **Tasks Listed:**
                - **Completed Tasks:**
                    - Buy groceries (due by 2025-10-19)
                - **Pending Tasks:**
                    - Finish the project report (due by 2025-10-20)
                    - Call Alice (due by 2025-10-21)`
    };

    Memory memory = check new ShortTermMemory(
        check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {
            model: new MockSummarizerModel(memorySummaryMessage)
        }
    );

    final string k = "key";

    final readonly & ChatUserMessage km1 = {
        role: USER,
        content: "Hello, what do I have on my plate today?"
    };

    final readonly & ChatAssistantMessage km2 = {
        role: ASSISTANT,
        toolCalls: [
            {
                name: "listTasks",
                arguments: {}
            }
        ]
    };

    final readonly & ChatFunctionMessage km3 = {
        role: FUNCTION,
        name: "listTasks",
        content: "[{\"description\":\"Buy groceries\",\"dueBy\":\"2025-10-19\",\"completed\":true}," +
            "{\"description\":\"Finish the project report\",\"dueBy\":\"2025-10-20\",\"completed\":false}," +
            "{\"description\":\"Call Alice\",\"dueBy\":\"2025-10-21\",\"completed\":false}]"
    };

    final readonly & ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: string `
            Today, you have the following task on your plate:

            1. **Finish the project report** - Due by **October 20, 2025**.

            Let me know if you need help with anything!`
    };
    check memory.update(k, [km1, km2, km3, km4]);

    ChatMessage[] k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 2);
    assertChatMessageEquals(k3CurrentMemory[0], memorySummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[1], km4);
}

// Tests preserving the last user message when summarizing on overflow.
@test:Config
function testShortTermMemoryWithSummarizationOnOverflow3() returns error? {
    final readonly & ChatAssistantMessage memorySummaryMessage = {
        role: ASSISTANT,
        content: string `Joy asked the AI for a book recommendation. The AI responded 
            by asking for Joy's preferred genre to provide a suitable suggestion.`
    };

    Memory memory = check new ShortTermMemory(
        check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {
            model: new MockSummarizerModel(memorySummaryMessage)
        }
    );
    
    final string k = "key";

    ChatUserMessage km1 = {
        role: USER,
        content: "Hello, I'm Joy. Can you recommend me a good book to read?"
    };
    check memory.update(k, km1);
    
    ChatAssistantMessage km2 = {
        role: ASSISTANT,
        content: "Hi Joy! Sure, what genre are you interested in?"
    };
    check memory.update(k, km2);

    ChatUserMessage km3 = {
        role: USER,
        content: "I enjoy science fiction and fantasy."
    };
    check memory.update(k, km3);

    ChatMessage[] k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 3);
    assertChatMessageEquals(k3CurrentMemory[0], km1);
    assertChatMessageEquals(k3CurrentMemory[1], km2);
    assertChatMessageEquals(k3CurrentMemory[2], km3);

    ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: string `Great choices! I recommend Arthur C. Clarke's '2001: A Space Odyssey' 
            for science fiction and J.R.R. Tolkien's 'The Hobbit' for fantasy.`
    };
    check memory.update(k, km4);

    k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 3);
    assertChatMessageEquals(k3CurrentMemory[0], memorySummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[1], km3);
    assertChatMessageEquals(k3CurrentMemory[2], km4);
}

@test:Config
function testShortTermMemoryWithSummarizationOnOverflow3OnBatchUpdate() returns error? {
    final readonly & ChatAssistantMessage memorySummaryMessage = {
        role: ASSISTANT,
        content: string `Joy asked the AI for a book recommendation. The AI responded 
            by asking for Joy's preferred genre to provide a suitable suggestion.`
    };

    Memory memory = check new ShortTermMemory(
        check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {
            model: new MockSummarizerModel(memorySummaryMessage)
        }
    );

    final string k = "key";

    ChatUserMessage km1 = {
        role: USER,
        content: "Hello, I'm Joy. Can you recommend me a good book to read?"
    };

    ChatAssistantMessage km2 = {
        role: ASSISTANT,
        content: "Hi Joy! Sure, what genre are you interested in?"
    };

    ChatUserMessage km3 = {
        role: USER,
        content: "I enjoy science fiction and fantasy."
    };

    ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: string `Great choices! I recommend Arthur C. Clarke's '2001: A Space Odyssey' 
            for science fiction and J.R.R. Tolkien's 'The Hobbit' for fantasy.`
    };
    check memory.update(k, [km1, km2, km3, km4]);

    ChatMessage[] k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 3);
    assertChatMessageEquals(k3CurrentMemory[0], memorySummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[1], km3);
    assertChatMessageEquals(k3CurrentMemory[2], km4);
}

@test:Config
function testOverridingSummarizationPrompt() returns error? {
    final readonly & Prompt customSummarizationPrompt = `Summarize the following conversation in brief: `;
    
    final readonly & ChatAssistantMessage mockSummaryMessage = {
        role: ASSISTANT,
        content: string `The user asked about their tasks for the day, and the assistant responded by 
        listing one task: to buy groceries, which is due by October 19, 2025, and is not yet completed.`
    };

    final string k = "key";

    final readonly & ChatUserMessage km1 = {
        role: USER, 
        content: "Hello, what do I have on my plate today?"
    };

    final readonly & ChatAssistantMessage km2 = {
        role: ASSISTANT,
        toolCalls: [
            {
                name: "listTasks",
                arguments: {}
            }
        ]
    };

    final readonly & ChatFunctionMessage km3 = {
        role: FUNCTION,
        name: "listTasks",
        content: "[{\"description\":\"Buy groceries\",\"dueBy\":\"2025-10-19\",\"completed\":false}]"
    };

    ModelProvider model = isolated client object {
        isolated remote function chat(
                ChatMessage[]|ChatUserMessage messages, 
                ChatCompletionFunctions[] tools, string? stop) returns ChatAssistantMessage|Error {
            assertSummarizationRequestChatMessages(messages, [km1, km2, km3], customSummarizationPrompt);
            return mockSummaryMessage;                    
        }

        isolated remote function generate(Prompt prompt, typedesc<anydata> td) returns td|Error = external;
    };

    Memory memory = check new ShortTermMemory(
        check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {
            model,
            prompt: customSummarizationPrompt
        }
    );

    check memory.update(k, km1);
    check memory.update(k, km2);
    check memory.update(k, km3);

    final readonly & ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: "You have one pending task: Buy groceries."
    };
    check memory.update(k, km4);

    ChatMessage[] k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 2);
    assertChatMessageEquals(k3CurrentMemory[0], mockSummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[1], km4);
}

@test:Config
function testDefaultingToTheDefaultModelForSummarization() returns error? {
    Memory|MemoryError memory = new ShortTermMemory(
        check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {
            prompt: `Summarize the following conversation briefly`
            // No model provided here, should default to the default model.
            // Since the model is not configured, should error out.
        }
    );

    if memory is Memory {
        test:assertFail("Expected 'MemoryError' but found 'Memory'");
    }

    test:assertEquals(memory.message(), 
        "Failed to initialize short term memory: The `ballerina.ai.wso2ProviderConfig` is not configured correctly. " +
            "Ensure values are configured for the WSO2 model provider configurable variable");
}

@test:Config
function testSummarizationFailure() returns error? {
    final string k = "key";

    final readonly & ChatUserMessage km1 = {
        role: USER, 
        content: "Hello, what do I have on my plate today?"
    };

    final readonly & ChatAssistantMessage km2 = {
        role: ASSISTANT,
        toolCalls: [
            {
                name: "listTasks",
                arguments: {}
            }
        ]
    };

    final readonly & ChatFunctionMessage km3 = {
        role: FUNCTION,
        name: "listTasks",
        content: "[{\"description\":\"Buy groceries\",\"dueBy\":\"2025-10-19\",\"completed\":false}]"
    };

    ModelProvider model = isolated client object {
        isolated remote function chat(
                ChatMessage[]|ChatUserMessage messages, 
                ChatCompletionFunctions[] tools, string? stop) returns ChatAssistantMessage|Error {
            assertSummarizationRequestChatMessages(messages, [km1, km2, km3], defaultSummarizationPrompt);
            return error("Simulated summarization failure");                    
        }

        isolated remote function generate(Prompt prompt, typedesc<anydata> td) returns td|Error = external;
    };

    Memory memory = check new ShortTermMemory(
        check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {model}
    );

    check memory.update(k, km1);
    check memory.update(k, km2);
    check memory.update(k, km3);

    final readonly & ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: "You have one pending task: Buy groceries."
    };
    MemoryError? err = memory.update(k, km4);
    if err is () {
        test:assertFail("Expected 'MemoryError' but found '()'");
    }

    test:assertEquals(err.message(), "Failed to generate summary: Simulated summarization failure");

    ChatMessage[] k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 3);
    assertChatMessageEquals(k3CurrentMemory[0], km1);
    assertChatMessageEquals(k3CurrentMemory[1], km2);
    assertChatMessageEquals(k3CurrentMemory[2], km3);
}

isolated function assertSummarizationRequestChatMessages(ChatMessage[]|ChatUserMessage messages, 
                                                         ChatInteractiveMessage[] expectedHistory,
                                                         Prompt summarizationPrompt) {
    if messages is ChatUserMessage {
        test:assertFail("Expected ChatMessage[] but found ChatUserMessage");
    }
    test:assertEquals(messages.length(), 2);
    
    ChatMessage message0 = messages[0];
    if message0 !is ChatSystemMessage {
        test:assertFail("Expected first message to be ChatSystemMessage");
    }
    string|Prompt prompt = message0.content;
    test:assertEquals(prompt is string ? prompt : toString(prompt), toString(summarizationPrompt));

    ChatMessage message1 = messages[1];
    if message1 !is ChatUserMessage {
        test:assertFail("Expected first message to be ChatUserMessage");
    }
    prompt = message1.content;
    test:assertEquals(prompt is string ? prompt : toString(prompt), 
                        toString(`Summarize this chat history: ${expectedHistory.toString()}`));
}

isolated client class MockSummarizerModel {
    *ModelProvider;

    final readonly & ChatAssistantMessage memorySummaryMessage;

    isolated function init(readonly & ChatAssistantMessage memorySummaryMessage) {
        self.memorySummaryMessage = memorySummaryMessage;
    }

    isolated remote function chat(
            ChatMessage[]|ChatUserMessage messages, 
            ChatCompletionFunctions[] tools, string? stop) returns ChatAssistantMessage|Error => 
                self.memorySummaryMessage;

    isolated remote function generate(Prompt prompt, typedesc<anydata> td) returns td|Error = external;
}
