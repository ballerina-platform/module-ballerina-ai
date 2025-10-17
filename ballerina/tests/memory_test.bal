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
