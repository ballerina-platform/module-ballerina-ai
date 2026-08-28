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

const string TRIGGER_STREAM_ERROR = "trigger-stream-error";

// Streams the SSE events collected in `events` one at a time.
class MockSseEventIterator {
    private final http:SseEvent[] events;
    private int index = 0;

    function init(http:SseEvent[] events) {
        self.events = events;
    }

    public isolated function next() returns record {|http:SseEvent value;|}|error? {
        lock {
            if self.index >= self.events.length() {
                return ();
            }
            http:SseEvent event = self.events[self.index];
            self.index += 1;
            return {value: event};
        }
    }

    public isolated function close() returns error? {
        return ();
    }
}

// Splits `MOCK_CHAT_TEXT_RESPONSE` across a couple of content deltas, then a finish chunk.
function mockTextStreamEvents() returns http:SseEvent[] => [
    {data: string `{"choices":[{"index":0,"delta":{"role":"assistant"}}]}`},
    {data: string `{"choices":[{"index":0,"delta":{"content":"Hello! "}}]}`},
    {data: string `{"choices":[{"index":0,"delta":{"content":"How can I help you today?"}}]}`},
    {
        data: string `{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],` +
            string `"usage":{"prompt_tokens":5,"completion_tokens":10,"total_tokens":15}}`
    },
    {data: "[DONE]"}
];

// Splits a `searchFunction({"query":"test"})` call's name and arguments across a few deltas.
function mockFunctionCallStreamEvents() returns http:SseEvent[] => [
    {data: string `{"choices":[{"index":0,"delta":{"role":"assistant"}}]}`},
    {data: string `{"choices":[{"index":0,"delta":{"function_call":{"name":"searchFunction"}}}]}`},
    {data: string `{"choices":[{"index":0,"delta":{"function_call":{"arguments":"{\"query\":"}}}]}`},
    {data: string `{"choices":[{"index":0,"delta":{"function_call":{"arguments":"\"test\"}"}}}]}`},
    {data: string `{"choices":[{"index":0,"delta":{},"finish_reason":"function_call"}]}`},
    {data: "[DONE]"}
];

// Mock intelligence service for Wso2ModelProvider tests.
// Returns a function-call response when the request contains `functions`, otherwise a plain text response.
// When the request has `stream: true`, responds with SSE chunks instead of a single JSON body; a user
// message containing `TRIGGER_STREAM_ERROR` makes the streaming path fail with a 500 to exercise error handling.
service on new http:Listener(MOCK_CHAT_PORT) {

    resource function post chat/completions(@http:Payload json payload, @http:Header string Authorization)
    returns json|stream<http:SseEvent, error?>|http:InternalServerError|error {
        if Authorization != "Bearer test-token" {
            return error("invalid authorization token");
        }
        json|error functions = payload.functions;
        boolean isFunctionCall = functions is json[] && functions.length() > 0;

        json|error streamFlag = payload.'stream;
        boolean isStreamRequest = streamFlag is boolean && streamFlag;

        if isStreamRequest {
            json|error messages = payload.messages;
            if messages is json[] && messages.length() > 0 && messages.toString().includes(TRIGGER_STREAM_ERROR) {
                return <http:InternalServerError>{body: {message: "simulated streaming failure"}};
            }
            http:SseEvent[] events = isFunctionCall ? mockFunctionCallStreamEvents() : mockTextStreamEvents();
            return new stream<http:SseEvent, error?>(new MockSseEventIterator(events));
        }

        if isFunctionCall {
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
function testWso2ModelProviderChatStreamWithUserMessage() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    stream<ChatCompletionChunk, Error?> chunkStream = check provider->chatStream({role: USER, content: "Hello"}, []);

    string content = "";
    ROLE? firstRole = ();
    FinishReason? lastFinishReason = ();
    while true {
        record {|ChatCompletionChunk value;|}|Error? next = chunkStream.next();
        if next is () {
            break;
        }
        if next is Error {
            test:assertFail("Unexpected error while streaming: " + next.message());
        }
        ChatCompletionChunkDelta delta = next.value.choices[0].delta;
        if firstRole is () && delta.role is ROLE {
            firstRole = delta.role;
        }
        string? deltaContent = delta.content;
        if deltaContent is string {
            content += deltaContent;
        }
        FinishReason? finishReason = next.value.choices[0].finishReason;
        if finishReason is FinishReason {
            lastFinishReason = finishReason;
        }
    }

    test:assertEquals(firstRole, ASSISTANT);
    test:assertEquals(content, MOCK_CHAT_TEXT_RESPONSE);
    test:assertEquals(lastFinishReason, STOP);
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatStreamWithTools() returns error? {
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
    stream<ChatCompletionChunk, Error?> chunkStream =
        check provider->chatStream({role: USER, content: "Search for test"}, tools);

    string accumulatedName = "";
    string accumulatedArguments = "";
    FinishReason? lastFinishReason = ();
    while true {
        record {|ChatCompletionChunk value;|}|Error? next = chunkStream.next();
        if next is () {
            break;
        }
        if next is Error {
            test:assertFail("Unexpected error while streaming: " + next.message());
        }
        ToolCallChunk[]? toolCalls = next.value.choices[0].delta.toolCalls;
        if toolCalls is ToolCallChunk[] && toolCalls.length() > 0 {
            FunctionCallChunk? functionCallChunk = toolCalls[0].'function;
            if functionCallChunk is FunctionCallChunk {
                string? name = functionCallChunk.name;
                if name is string {
                    accumulatedName += name;
                }
                string? args = functionCallChunk.arguments;
                if args is string {
                    accumulatedArguments += args;
                }
            }
        }
        FinishReason? finishReason = next.value.choices[0].finishReason;
        if finishReason is FinishReason {
            lastFinishReason = finishReason;
        }
    }

    test:assertEquals(accumulatedName, "searchFunction");
    map<json> parsedArguments = check accumulatedArguments.fromJsonStringWithType();
    test:assertEquals(parsedArguments["query"], "test");
    test:assertEquals(lastFinishReason, TOOL_CALLS);
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatStreamConnectionError() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    stream<ChatCompletionChunk, Error?>|Error result =
        provider->chatStream({role: USER, content: TRIGGER_STREAM_ERROR}, []);
    test:assertTrue(result is Error, "Expected an error when the streaming connection fails");
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderGenerateStreamWithUserMessage() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    stream<string, Error?> textStream = check provider->generateStream(`Hello`);

    string content = "";
    while true {
        record {|string value;|}|Error? next = textStream.next();
        if next is () {
            break;
        }
        if next is Error {
            test:assertFail("Unexpected error while streaming: " + next.message());
        }
        content += next.value;
    }
    test:assertEquals(content, MOCK_CHAT_TEXT_RESPONSE);
}
