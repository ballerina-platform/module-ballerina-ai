// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
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

import ballerina/http;
import ballerina/test;

const int MOCK_CHAT_PORT = 9096;
const MOCK_CHAT_URL = "http://localhost:9096";

const MOCK_CHAT_TEXT_RESPONSE = "Hello! How can I help you today?";
const MOCK_CONTEXT_LENGTH_ERROR = "This model's maximum context length is 128000 tokens. However, your messages " +
    "resulted in 178766 tokens. Please reduce the length of the messages or functions.";

// Mock intelligence service for Wso2ModelProvider tests.
// Returns a function-call response when the request contains `functions`, otherwise a plain text response.
service on new http:Listener(MOCK_CHAT_PORT) {

    resource function post chat/completions(@http:Payload json payload, @http:Header string Authorization)
    returns json|http:BadRequest|http:Unauthorized|error {
        if Authorization == "Bearer context-overflow-token" {
            return <http:BadRequest>{
                body: {
                    'error: {
                        message: MOCK_CONTEXT_LENGTH_ERROR,
                        'type: "invalid_request_error",
                        param: "messages",
                        code: "context_length_exceeded"
                    }
                }
            };
        }
        if Authorization == "Bearer expired-token" {
            return <http:Unauthorized>{body: {code: "900901", description: "Invalid Credentials"}};
        }
        if Authorization != "Bearer test-token" {
            return error("invalid authorization token");
        }
        json|error functions = payload.functions;
        if functions is json[] && functions.length() > 0 {
            return {
                id: "resp-func-call",
                'object: "chat.completion",
                created: 1700000000,
                model: "gpt-4o-mini",
                choices: [
                    {
                        index: 0,
                        message: {
                            role: "assistant",
                            content: (),
                            function_call: {
                                name: "searchFunction",
                                arguments: "{\"query\":\"test\"}"
                            }
                        },
                        finish_reason: "function_call"
                    }
                ],
                usage: {prompt_tokens: 5, completion_tokens: 10, total_tokens: 15}
            };
        }
        return {
            id: "resp-text",
            'object: "chat.completion",
            created: 1700000000,
            model: "gpt-4o-mini",
            choices: [
                {
                    index: 0,
                    message: {
                        role: "assistant",
                        content: MOCK_CHAT_TEXT_RESPONSE
                    },
                    finish_reason: "stop"
                }
            ],
            usage: {prompt_tokens: 5, completion_tokens: 10, total_tokens: 15}
        };
    }
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatWithUserMessage() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    ChatAssistantMessage response = check provider->chat({role: USER, content: "Hello"}, []);
    test:assertEquals(response.role, ASSISTANT);
    test:assertEquals(response.content, MOCK_CHAT_TEXT_RESPONSE);
    test:assertTrue(response.toolCalls is (), "Expected no tool calls for plain text response");
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatWithMultipleMessages() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    ChatMessage[] messages = [
        {role: SYSTEM, content: "You are a helpful assistant."},
        {role: USER, content: "Hello"}
    ];
    ChatAssistantMessage response = check provider->chat(messages, []);
    test:assertEquals(response.role, ASSISTANT);
    test:assertEquals(response.content, MOCK_CHAT_TEXT_RESPONSE);
    test:assertTrue(response.toolCalls is (), "Expected no tool calls");
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatWithCustomTemperature() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token", temperature = 0.2d);
    ChatAssistantMessage response = check provider->chat({role: USER, content: "Hello"}, []);
    test:assertEquals(response.role, ASSISTANT);
    test:assertEquals(response.content, MOCK_CHAT_TEXT_RESPONSE);
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatWithTools() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    ChatCompletionFunctions[] tools = [
        {
            name: "searchFunction",
            description: "Search for information",
            parameters: {
                'type: "object",
                properties: {query: {'type: "string"}}
            }
        }
    ];
    ChatAssistantMessage response = check provider->chat({role: USER, content: "Search for test"}, tools);
    test:assertEquals(response.role, ASSISTANT);
    FunctionCall[]? toolCalls = response.toolCalls;
    if toolCalls is () || toolCalls.length() == 0 {
        test:assertFail("Expected tool calls in the response");
    }
    test:assertEquals(toolCalls[0].name, "searchFunction");
    map<json>? args = toolCalls[0].arguments;
    if args is () {
        test:assertFail("Expected arguments in tool call");
    }
    test:assertEquals(args["query"], "test");
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatErrorIncludesProviderMessage() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "context-overflow-token");
    ChatAssistantMessage|Error response = provider->chat({role: USER, content: "Hello"}, []);
    if response !is LlmConnectionError {
        test:assertFail("Expected an LlmConnectionError");
    }
    test:assertEquals(response.message(), "Error while connecting to the model: " + MOCK_CONTEXT_LENGTH_ERROR);
    test:assertTrue(response.cause() is http:ApplicationResponseError);
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatErrorIncludesNonOpenAiErrorBody() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "expired-token");
    ChatAssistantMessage|Error response = provider->chat({role: USER, content: "Hello"}, []);
    if response !is LlmConnectionError {
        test:assertFail("Expected an LlmConnectionError");
    }
    test:assertEquals(response.message(),
        "Error while connecting to the model: {\"code\":\"900901\", \"description\":\"Invalid Credentials\"}");
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testAgentRunErrorSurfacesModelError() returns error? {
    Wso2ModelProvider model = check new (MOCK_CHAT_URL, "context-overflow-token");
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Answer the questions"},
        model,
        tools: []
    });
    string|Error result = agent.run("Hello");
    if result is string {
        test:assertFail("Expected the agent run to fail");
    }
    test:assertEquals(result.message(), "Unable to obtain valid answer from the agent: " +
        "Error while connecting to the model: " + MOCK_CONTEXT_LENGTH_ERROR);
    test:assertTrue(result.cause() is LlmConnectionError);
}
