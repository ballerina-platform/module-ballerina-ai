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
