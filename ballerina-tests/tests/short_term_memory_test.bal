import ballerina/ai;
import ballerina/test;

const string SUMMARY_PREFIX = "Summary of previous interactions:";
const DEFAULT_SESSION_ID = "default-session-id";
const MEMORY_PROVIDER_SERVICE_URL = "http://localhost:8080/llm/azureopenai/deployments/gpt4onew/memory/summarization";
const MEMORY_ERROR_PROVIDER_SERVICE_URL = "http://localhost:8080/llm/azureopenai/deployments/gpt4onew/memory-error";
const MEMORY_PROVIDER_API_KEY = "not-a-real-api-key";
final ai:Wso2ModelProvider memoryModelProvider = check new (MEMORY_PROVIDER_SERVICE_URL, MEMORY_PROVIDER_API_KEY);
final ai:Wso2ModelProvider memoryModelProvider2 = check new (MEMORY_ERROR_PROVIDER_SERVICE_URL, MEMORY_PROVIDER_API_KEY);

@test:Config {}
function testMemoryInitializationWithSummarization() returns error? {
    ai:MessageWindowChatMemory chatMemory = new (5, {
        modelProvider: memoryModelProvider
    });

    ai:ChatMessage[] history = check chatMemory.get(DEFAULT_SESSION_ID);
    int memoryLength = history.length();
    test:assertEquals(memoryLength, 0);
}

@test:Config {}
function testMemoryUpdateSystemMesageWithSummarization() returns error? {
    ai:MessageWindowChatMemory chatMemory = new (5, {
        modelProvider: memoryModelProvider
    });

    ai:ChatUserMessage userMessage = {role: "user", content: "Hi I'm bob"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage);
    ai:ChatAssistantMessage assistantMessage = {role: "assistant", content: "Hello Bob! How can I assist you today?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage);
    ai:ChatSystemMessage systemMessage = {
        role: "system",
        content: `You are an AI assistant to help users get answers. Respond to the human as helpfully and accurately as possible`
    };
    _ = check chatMemory.update(DEFAULT_SESSION_ID, systemMessage);
    ai:ChatMessage[] history = check chatMemory.get(DEFAULT_SESSION_ID);
    assertChatMessageEquals(history[0], systemMessage);
    test:assertEquals(history.length(), 3);
}

@test:Config {}
function testClearMemoryWithSummarization() returns error? {
    ai:MessageWindowChatMemory chatMemory = new (4, {
        modelProvider: memoryModelProvider
    });
    ai:ChatUserMessage userMessage = {role: "user", content: "Hi I'm bob"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage);
    ai:ChatAssistantMessage assistantMessage = {role: "assistant", content: "Hello Bob! How can I assist you today?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage);
    ai:ChatSystemMessage systemMessage = {role: "system", content: "You are an AI assistant to help users get answers. Respond to the human as helpfully and accurately as possible"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, systemMessage);
    _ = check chatMemory.delete(DEFAULT_SESSION_ID);
    test:assertEquals(chatMemory.get(DEFAULT_SESSION_ID), []);
}

@test:Config {}
function testClearEmptyMemoryWithSummarization() returns error? {
    ai:MessageWindowChatMemory chatMemory = new (4, {
        modelProvider: memoryModelProvider
    });
    _ = check chatMemory.delete(DEFAULT_SESSION_ID);
    test:assertEquals(chatMemory.get(DEFAULT_SESSION_ID), []);
}

@test:Config {}
function testMemoryUpdateWithSizeFive() returns error? {
    ai:MessageWindowChatMemory chatMemory = new (5, {
        modelProvider: memoryModelProvider
    });

    ai:ChatUserMessage userMessage1 = {role: "user", content: "How do I make a pizza?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage1);
    ai:ChatAssistantMessage assistantMessage1 = {role: "assistant", content: "First, you need dough."};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage1);

    ai:ChatSystemMessage systemMessage = {
        role: "system",
        content: "You are a culinary assistant."
    };
    _ = check chatMemory.update(DEFAULT_SESSION_ID, systemMessage);
    ai:ChatMessage[] history1 = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history1.length(), 3);
    assertChatMessageEquals(history1[0], systemMessage);
    assertChatMessageEquals(history1[1], userMessage1);
    assertChatMessageEquals(history1[2], assistantMessage1);

    ai:ChatUserMessage userMessage2 = {role: "user", content: "What about the sauce?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage2);
    ai:ChatAssistantMessage assistantMessage2 = {role: "assistant", content: "You can use a simple tomato sauce."};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage2);
    ai:ChatMessage[] history2 = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history2.length(), 5);
    assertChatMessageEquals(history2[0], systemMessage);
    assertChatMessageEquals(history2[1], userMessage1);
    assertChatMessageEquals(history2[2], assistantMessage1);
    assertChatMessageEquals(history2[3], userMessage2);
    assertChatMessageEquals(history2[4], assistantMessage2);

    ai:ChatUserMessage userMessage3 = {role: "user", content: "And the toppings?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage3);
    ai:ChatAssistantMessage assistantMessage3 = {role: "assistant", content: "Popular toppings include pepperoni and mushrooms."};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage3);
    ai:ChatMessage[] history3 = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history3.length(), 5);
    assertChatMessageEquals(history3[0], systemMessage);
    test:assertEquals(history3[1], {role: ai:USER, content: SUMMARY_PREFIX + " <Summary>"});
    assertChatMessageEquals(history3[2], assistantMessage2);
    assertChatMessageEquals(history3[3], userMessage3);
    assertChatMessageEquals(history3[4], assistantMessage3);

    ai:ChatUserMessage userMessage4 = {role: "user", content: "Thanks!"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage4);
    ai:ChatAssistantMessage assistantMessage4 = {role: "assistant", content: "You're welcome!"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage4);
    ai:ChatMessage[] history4 = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history4.length(), 5);
    assertChatMessageEquals(history4[0], systemMessage);
    test:assertEquals(history4[1], {role: ai:USER, content: SUMMARY_PREFIX + " <Summary>"});
    assertChatMessageEquals(history4[2], assistantMessage3);
    assertChatMessageEquals(history4[3], userMessage4);
    assertChatMessageEquals(history4[4], assistantMessage4);
}

@test:Config {}
function testMemoryUpdateWithSizeSix() returns error? {
    ai:MessageWindowChatMemory chatMemory = new (6, {
        modelProvider: memoryModelProvider
    });

    ai:ChatUserMessage userMessage1 = {role: "user", content: "How do I make a pizza?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage1);
    ai:ChatAssistantMessage assistantMessage1 = {role: "assistant", content: "First, you need dough."};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage1);

    ai:ChatSystemMessage systemMessage = {
        role: "system",
        content: "You are a culinary assistant."
    };
    _ = check chatMemory.update(DEFAULT_SESSION_ID, systemMessage);
    ai:ChatMessage[] history1 = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history1.length(), 3);
    assertChatMessageEquals(history1[0], systemMessage);
    assertChatMessageEquals(history1[1], userMessage1);
    assertChatMessageEquals(history1[2], assistantMessage1);

    ai:ChatUserMessage userMessage2 = {role: "user", content: "What about the sauce?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage2);
    ai:ChatAssistantMessage assistantMessage2 = {role: "assistant", content: "You can use a simple tomato sauce."};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage2);
    ai:ChatMessage[] history2 = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history2.length(), 5);
    assertChatMessageEquals(history2[0], systemMessage);
    assertChatMessageEquals(history2[1], userMessage1);
    assertChatMessageEquals(history2[2], assistantMessage1);
    assertChatMessageEquals(history2[3], userMessage2);
    assertChatMessageEquals(history2[4], assistantMessage2);

    ai:ChatUserMessage userMessage3 = {role: "user", content: "And the toppings?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage3);
    ai:ChatAssistantMessage assistantMessage3 = {role: "assistant", content: "Popular toppings include pepperoni and mushrooms."};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage3);
    ai:ChatMessage[] history3 = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history3.length(), 3);
    assertChatMessageEquals(history3[0], systemMessage);
    test:assertEquals(history3[1], {role: ai:USER, content: SUMMARY_PREFIX + " <Summary>"});
    assertChatMessageEquals(history3[2], assistantMessage3);

    ai:ChatUserMessage userMessage4 = {role: "user", content: "Thanks!"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage4);
    ai:ChatAssistantMessage assistantMessage4 = {role: "assistant", content: "You're welcome!"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage4);
    ai:ChatUserMessage userMessage5 = {role: "user", content: "One more question, please."};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage5);
    ai:ChatAssistantMessage assistantMessage5 = {role: "assistant", content: "Sure, go ahead!"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage5);

    ai:ChatMessage[] history4 = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history4.length(), 3);
    assertChatMessageEquals(history3[0], systemMessage);
    test:assertEquals(history3[1], {role: ai:USER, content: SUMMARY_PREFIX + " <Summary>"});
    assertChatMessageEquals(history3[2], assistantMessage5);
}

@test:Config {}
function testMemoryUpdateWithSizeThree() returns error? {
    ai:MessageWindowChatMemory chatMemory = new (3, {
        modelProvider: memoryModelProvider
    });

    ai:ChatSystemMessage systemMessage = {
        role: "system",
        content: "You are a culinary assistant."
    };
    _ = check chatMemory.update(DEFAULT_SESSION_ID, systemMessage);

    ai:ChatUserMessage userMessage1 = {role: "user", content: "How do I make a pizza?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage1);
    ai:ChatMessage[] history1 = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history1.length(), 2);
    assertChatMessageEquals(history1[0], systemMessage);
    assertChatMessageEquals(history1[1], userMessage1);

    ai:ChatAssistantMessage assistantMessage1 = {role: "assistant", content: "First, you need dough."};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage1);
    ai:ChatMessage[] history2 = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history2.length(), 3);
    assertChatMessageEquals(history1[0], systemMessage);
    assertChatMessageEquals(history2[1], userMessage1);
    assertChatMessageEquals(history2[2], assistantMessage1);

    ai:ChatUserMessage userMessage2 = {role: "user", content: "What about the sauce?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage2);
    ai:ChatMessage[] history4 = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history4.length(), 3);
    assertChatMessageEquals(history4[0], systemMessage);
    assertChatMessageEquals(history4[1], assistantMessage1);
    assertChatMessageEquals(history4[2], userMessage2);

    ai:ChatAssistantMessage assistantMessage2 = {role: "assistant", content: "You can use tomato sauce."};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage2);
    ai:ChatMessage[] history5 = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history5.length(), 3);
    assertChatMessageEquals(history5[0], systemMessage);
    assertChatMessageEquals(history5[1], userMessage2);
    assertChatMessageEquals(history5[2], assistantMessage2);

    ai:ChatUserMessage userMessage3 = {role: "user", content: "Any topping suggestions?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage3);
    ai:ChatMessage[] history6 = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history6.length(), 3);
    assertChatMessageEquals(history6[0], systemMessage);
    assertChatMessageEquals(history6[1], assistantMessage2);
    assertChatMessageEquals(history6[2], userMessage3);

    ai:ChatAssistantMessage assistantMessage3 = {role: "assistant", content: "Try pepperoni or mushrooms."};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage3);
    ai:ChatMessage[] history7 = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history7.length(), 3);
    assertChatMessageEquals(history7[0], systemMessage);
    assertChatMessageEquals(history7[1], userMessage3);
    assertChatMessageEquals(history7[2], assistantMessage3);
}

@test:Config {}
function testMemoryUpdateWithSizeTwo() returns error? {
    ai:MessageWindowChatMemory chatMemory = new (2, {
        modelProvider: memoryModelProvider
    });

    ai:ChatUserMessage userMessage1 = {role: "user", content: "Hello there!"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage1);

    ai:ChatSystemMessage systemMessage = {
        role: "system",
        content: "You are a helpful assistant."
    };
    _ = check chatMemory.update(DEFAULT_SESSION_ID, systemMessage);
    ai:ChatMessage[] history = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history.length(), 2);
    assertChatMessageEquals(history[0], systemMessage);
    assertChatMessageEquals(history[1], userMessage1);

    ai:ChatAssistantMessage assistantMessage1 = {role: "assistant", content: "Hello! How can I help you?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage1);
    history = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history.length(), 2);
    assertChatMessageEquals(history[0], systemMessage);
    assertChatMessageEquals(history[1], assistantMessage1);

    ai:ChatUserMessage userMessage2 = {role: "user", content: "What's the weather like?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage2);
    history = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history.length(), 2);
    assertChatMessageEquals(history[0], systemMessage);
    assertChatMessageEquals(history[1], userMessage2);

    ai:ChatAssistantMessage assistantMessage2 = {role: "assistant", content: "I don't have access to weather data."};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage2);
    history = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history.length(), 2);
    assertChatMessageEquals(history[0], systemMessage);
    assertChatMessageEquals(history[1], assistantMessage2);

    ai:ChatFunctionMessage functionMessage = {role: "function", content: "Function result", name: "get_weather", id: "func_123"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, functionMessage);
    history = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history.length(), 2);
    assertChatMessageEquals(history[0], systemMessage);
    assertChatMessageEquals(history[1], functionMessage);

    ai:ChatUserMessage userMessage3 = {role: "user", content: "Thank you!"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage3);
    history = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history.length(), 2);
    assertChatMessageEquals(history[0], systemMessage);
    assertChatMessageEquals(history[1], userMessage3);
}

@test:Config {}
function testMemoryUpdateWithSizeFiveWhenSummarizationFails() returns error? {
    ai:MessageWindowChatMemory chatMemory = new (5, {
        modelProvider: memoryModelProvider2
    });

    ai:ChatUserMessage userMessage1 = {role: "user", content: "How do I make a pizza?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage1);
    ai:ChatAssistantMessage assistantMessage1 = {role: "assistant", content: "First, you need dough."};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage1);

    ai:ChatSystemMessage systemMessage = {
        role: "system",
        content: "You are a culinary assistant."
    };
    _ = check chatMemory.update(DEFAULT_SESSION_ID, systemMessage);
    ai:ChatMessage[] history = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history.length(), 3);
    assertChatMessageEquals(history[0], systemMessage);
    assertChatMessageEquals(history[1], userMessage1);
    assertChatMessageEquals(history[2], assistantMessage1);

    ai:ChatUserMessage userMessage2 = {role: "user", content: "What about the sauce?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage2);
    ai:ChatAssistantMessage assistantMessage2 = {role: "assistant", content: "You can use a simple tomato sauce."};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage2);
    ai:ChatUserMessage userMessage3 = {role: "user", content: "And the toppings?"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage3);
    history = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history.length(), 5);
    assertChatMessageEquals(history[0], systemMessage);
    assertChatMessageEquals(history[1], assistantMessage1);
    assertChatMessageEquals(history[2], userMessage2);
    assertChatMessageEquals(history[3], assistantMessage2);
    assertChatMessageEquals(history[4], userMessage3);

    ai:ChatAssistantMessage assistantMessage3 = {role: "assistant", content: "Popular toppings include pepperoni and mushrooms."};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage3);
    ai:ChatUserMessage userMessage4 = {role: "user", content: "Thanks!"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, userMessage4);
    history = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history.length(), 5);
    assertChatMessageEquals(history[0], systemMessage);
    assertChatMessageEquals(history[1], assistantMessage2);
    assertChatMessageEquals(history[2], userMessage3);
    assertChatMessageEquals(history[3], assistantMessage3);
    assertChatMessageEquals(history[4], userMessage4);

    ai:ChatAssistantMessage assistantMessage4 = {role: "assistant", content: "You're welcome!"};
    _ = check chatMemory.update(DEFAULT_SESSION_ID, assistantMessage4);
    history = check chatMemory.get(DEFAULT_SESSION_ID);
    test:assertEquals(history.length(), 5);
    assertChatMessageEquals(history[0], systemMessage);
    assertChatMessageEquals(history[1], userMessage3);
    assertChatMessageEquals(history[2], assistantMessage3);
    assertChatMessageEquals(history[3], userMessage4);
    assertChatMessageEquals(history[4], assistantMessage4);
}

isolated function assertChatMessageEquals(ai:ChatMessage actual, ai:ChatMessage expected) {
    if actual is ai:ChatUserMessage && expected is ai:ChatUserMessage {
        test:assertEquals(actual.role, expected.role);
        assertContentEquals(actual.content, expected.content);
        test:assertEquals(actual.name, expected.name);
        return;
    }
    if actual is ai:ChatSystemMessage && expected is ai:ChatSystemMessage {
        test:assertEquals(actual.role, expected.role);
        assertContentEquals(actual.content, expected.content);
        test:assertEquals(actual.name, expected.name);
        return;
    }
    if actual is ai:ChatFunctionMessage && expected is ai:ChatFunctionMessage {
        test:assertEquals(actual.role, expected.role);
        test:assertEquals(actual.name, expected.name);
        test:assertEquals(actual.id, expected.id);
        return;
    }
    if actual is ai:ChatAssistantMessage && expected is ai:ChatAssistantMessage {
        test:assertEquals(actual.role, expected.role);
        test:assertEquals(actual.name, expected.name);
        test:assertEquals(actual.toolCalls, expected.toolCalls);
        return;
    }
    test:assertFail("Actual and expected ChatMessage types do not match");
}

isolated function assertContentEquals(ai:Prompt|string actual, ai:Prompt|string expected) {
    if actual is string && expected is string {
        test:assertEquals(actual, expected);
        return;
    }
    if actual is ai:Prompt && expected is ai:Prompt {
        test:assertEquals(actual.strings, expected.strings);
        test:assertEquals(actual.insertions, expected.insertions);
        return;
    }
    test:assertFail("Actual and expected content do not match");
}
