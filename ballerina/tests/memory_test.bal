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
function testShortTermMemoryWithInMemoryStoreCustomTrimmingOnOverflow() returns error? {
    InMemoryShortTermMemoryStore store = check new (3);
    Memory memory = check new ShortTermMemory(store, <OverflowTrimConfiguration>{trimCount: 3});

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

const CHAT_METHOD = "chat";

@test:Config
function testShortTermMemoryWithSummarizationOnOverflow1() returns error? {
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

    InMemoryShortTermMemoryStore store = check new (4);
    ModelProvider model = isolated client object {
        isolated remote function chat(
                ChatMessage[]|ChatUserMessage messages, 
                ChatCompletionFunctions[] tools, string? stop) returns ChatAssistantMessage|Error => 
                    memorySummaryMessage;

        isolated remote function generate(Prompt prompt, typedesc<anydata> td) returns td|Error = external;
    };

    Memory memory = check new ShortTermMemory(
        store,
        overflowConfiguration = {
            model
        }
    );
    
    final string k = "key";
    final readonly & ChatSystemMessage ksm1 = {
        role: SYSTEM, 
        content: string `
            # Role  
            Task Assistant  

            # Instructions  
            You are a helpful assistant that guides users with their todo lists.`
    };
    check memory.update(k, ksm1);

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

    final readonly & ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: string `
            Today, you have the following task on your plate:

            1. **Finish the project report** - Due by **October 20, 2025**.

            Let me know if you need help with anything!`
    };
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
    test:assertEquals(k3CurrentMemory.length(), 4);
    assertChatMessageEquals(k3CurrentMemory[0], ksm1);
    assertChatMessageEquals(k3CurrentMemory[1], memorySummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[2], km4);
    assertChatMessageEquals(k3CurrentMemory[3], km5);
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

    InMemoryShortTermMemoryStore store = check new (3);
    ModelProvider model = isolated client object {
        isolated remote function chat(
                ChatMessage[]|ChatUserMessage messages, 
                ChatCompletionFunctions[] tools, string? stop) returns ChatAssistantMessage|Error => 
                    memorySummaryMessage;

        isolated remote function generate(Prompt prompt, typedesc<anydata> td) returns td|Error = external;
    };

    Memory memory = check new ShortTermMemory(
        store,
        overflowConfiguration = {
            model
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
