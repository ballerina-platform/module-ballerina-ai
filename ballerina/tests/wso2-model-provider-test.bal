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

// Mock intelligence service for Wso2ModelProvider tests.
// Echoes the request messages back as the content when the last message is a tool result, returns parallel
// tool calls when the request contains `tools`, and otherwise returns a plain text response.
service on new http:Listener(MOCK_CHAT_PORT) {

    resource function post chat/completions(@http:Payload json payload, @http:Header string Authorization)
    returns json|error {
        if Authorization != "Bearer test-token" {
            return error("invalid authorization token");
        }
        if payload.functions is json || payload.function_call is json {
            return error("legacy `functions` API must not be used");
        }
        json[] messages = check payload.messages.ensureType();
        if messages.length() > 0 && check messages[messages.length() - 1].role == "tool" {
            return getMockTextResponse(messages.toJsonString());
        }
        json|error tools = payload.tools;
        if tools is json[] && tools.length() > 0 {
            foreach json tool in tools {
                if check tool.'type != "function" || check tool.'function.name !is string {
                    return error("invalid tool definition: " + tool.toJsonString());
                }
            }
            return {
                id: "resp-tool-calls",
                'object: "chat.completion",
                created: 1700000000,
                model: "gpt-4o-mini",
                choices: [
                    {
                        index: 0,
                        message: {
                            role: "assistant",
                            content: (),
                            tool_calls: [
                                {
                                    id: "call_search",
                                    'type: "function",
                                    'function: {name: "searchFunction", arguments: "{\"query\":\"test\"}"}
                                },
                                {
                                    id: "call_weather",
                                    'type: "function",
                                    'function: {name: "getWeather", arguments: "{\"city\":\"London\"}"}
                                }
                            ]
                        },
                        finish_reason: "tool_calls"
                    }
                ],
                usage: {prompt_tokens: 5, completion_tokens: 10, total_tokens: 15}
            };
        }
        return getMockTextResponse(MOCK_CHAT_TEXT_RESPONSE);
    }
}

isolated function getMockTextResponse(string content) returns json => {
    id: "resp-text",
    'object: "chat.completion",
    created: 1700000000,
    model: "gpt-4o-mini",
    choices: [
        {
            index: 0,
            message: {
                role: "assistant",
                content
            },
            finish_reason: "stop"
        }
    ],
    usage: {prompt_tokens: 5, completion_tokens: 10, total_tokens: 15}
};

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
function testWso2ModelProviderChatWithParallelToolCalls() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    ChatCompletionFunctions[] tools = [
        {
            name: "searchFunction",
            description: "Search for information",
            parameters: {'type: "object", properties: {query: {'type: "string"}}}
        },
        {
            name: "getWeather",
            description: "Get the weather for a city",
            parameters: {'type: "object", properties: {city: {'type: "string"}}}
        }
    ];
    ChatAssistantMessage response = check provider->chat(
        {role: USER, content: "Search for test and get the weather in London"}, tools);
    FunctionCall[]? toolCalls = response.toolCalls;
    if toolCalls is () {
        test:assertFail("Expected tool calls in the response");
    }
    test:assertEquals(toolCalls, [
        {name: "searchFunction", arguments: {query: "test"}, id: "call_search"},
        {name: "getWeather", arguments: {city: "London"}, id: "call_weather"}
    ]);
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatMapsParallelToolCallHistory() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    ChatMessage[] messages = [
        {role: USER, content: "Search for test and get the weather in London"},
        {
            role: ASSISTANT,
            toolCalls: [
                {name: "searchFunction", arguments: {query: "test"}, id: "call_search"},
                {name: "getWeather", arguments: {city: "London"}, id: "call_weather"}
            ]
        },
        {role: FUNCTION, name: "searchFunction", content: "search result", id: "call_search"},
        {role: FUNCTION, name: "getWeather", content: "sunny", id: "call_weather"}
    ];
    ChatAssistantMessage response = check provider->chat(messages, []);
    string? content = response.content;
    if content is () {
        test:assertFail("Expected the mock to echo the request messages");
    }
    json[] sentMessages = check (check content.fromJsonString()).ensureType();
    test:assertEquals(sentMessages.length(), 4);
    test:assertEquals(sentMessages[1], {
        role: "assistant",
        tool_calls: [
            {
                id: "call_search",
                'type: "function",
                'function: {name: "searchFunction", arguments: "{\"query\":\"test\"}"}
            },
            {
                id: "call_weather",
                'type: "function",
                'function: {name: "getWeather", arguments: "{\"city\":\"London\"}"}
            }
        ]
    });
    test:assertEquals(sentMessages[2], {role: "tool", tool_call_id: "call_search", content: "search result"});
    test:assertEquals(sentMessages[3], {role: "tool", tool_call_id: "call_weather", content: "sunny"});
}
