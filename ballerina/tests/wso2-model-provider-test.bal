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

import ai.observe;

import ballerina/http;
import ballerina/test;

const int MOCK_CHAT_PORT = 9096;
const MOCK_CHAT_URL = "http://localhost:9096";
// Nothing listens on this port, so requests to it fail to connect.
const UNREACHABLE_CHAT_URL = "http://localhost:9199";

const MOCK_CHAT_TEXT_RESPONSE = "Hello! How can I help you today?";
const MOCK_STREAM_TEXT_ID = "chatcmpl-text";
const MOCK_STREAM_TOOL_ID = "chatcmpl-tool";

const string TRIGGER_STREAM_ERROR = "trigger-stream-error";
const string TRIGGER_MALFORMED_CHUNK = "trigger-malformed-chunk";
const string TRIGGER_PROVIDER_ERROR = "trigger-provider-error";
const string TRIGGER_IMAGE_PROMPT = "trigger-image-prompt";
const MOCK_PROVIDER_ERROR_MESSAGE = "provider failed";
const MOCK_IMAGE_URL = "https://example.com/cat.png";

// Streams the SSE events collected in `events` one at a time and records whether it was closed.
// With `dropConnection`, returns an error once the events run out, as a dropped connection would.
class MockSseEventIterator {
    private final http:SseEvent[] events;
    private final boolean dropConnection;
    private int index = 0;
    private boolean closed = false;

    function init(http:SseEvent[] events, boolean dropConnection = false) {
        self.events = events;
        self.dropConnection = dropConnection;
    }

    public isolated function next() returns record {|http:SseEvent value;|}|error? {
        lock {
            if self.index >= self.events.length() {
                return self.dropConnection ? error("connection reset by peer") : ();
            }
            http:SseEvent event = self.events[self.index];
            self.index += 1;
            return {value: event};
        }
    }

    public isolated function close() returns error? {
        lock {
            self.closed = true;
        }
    }

    isolated function isClosed() returns boolean {
        lock {
            return self.closed;
        }
    }
}

// Splits `MOCK_CHAT_TEXT_RESPONSE` across two content deltas, then a finish chunk. The role-only
// opening delta, the keep-alive comment and the trailing usage-only event carry nothing for the
// caller and must not surface as chunks.
function mockTextStreamEvents() returns http:SseEvent[] => [
    {data: string `{"id":"${MOCK_STREAM_TEXT_ID}","choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}`},
    {data: string `{"id":"${MOCK_STREAM_TEXT_ID}","choices":[{"index":0,"delta":{"content":"Hello! "}}]}`},
    {comment: "keep-alive"},
    {data: string `{"id":"${MOCK_STREAM_TEXT_ID}","choices":[{"index":0,"delta":{"content":"How can I help you today?"}}]}`},
    {data: string `{"id":"${MOCK_STREAM_TEXT_ID}","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":null}`},
    {
        data: string `{"id":"${MOCK_STREAM_TEXT_ID}","choices":[],` +
            string `"usage":{"prompt_tokens":5,"completion_tokens":10,"total_tokens":15}}`
    },
    {data: "[DONE]"}
];

// Splits a `searchFunction({"query":"test"})` call's name and arguments across a few deltas.
function mockFunctionCallStreamEvents() returns http:SseEvent[] => [
    {data: string `{"id":"${MOCK_STREAM_TOOL_ID}","choices":[{"index":0,"delta":{"role":"assistant","content":null}}]}`},
    {
        data: string `{"id":"${MOCK_STREAM_TOOL_ID}","choices":[{"index":0,` +
            string `"delta":{"function_call":{"name":"searchFunction","arguments":""}}}]}`
    },
    {data: string `{"id":"${MOCK_STREAM_TOOL_ID}","choices":[{"index":0,"delta":{"function_call":{"arguments":"{\"query\":"}}}]}`},
    {data: string `{"id":"${MOCK_STREAM_TOOL_ID}","choices":[{"index":0,"delta":{"function_call":{"arguments":"\"test\"}"}}}]}`},
    {data: string `{"id":"${MOCK_STREAM_TOOL_ID}","choices":[{"index":0,"delta":{},"finish_reason":"function_call"}]}`},
    {data: "[DONE]"}
];

// A well-formed content chunk followed by a payload that is not valid JSON.
function mockMalformedStreamEvents() returns http:SseEvent[] => [
    {data: string `{"id":"chatcmpl-bad","choices":[{"index":0,"delta":{"content":"partial"}}]}`},
    {data: "{not-json"},
    {data: "[DONE]"}
];

// A well-formed content chunk followed by a provider error payload that carries no choices.
function mockProviderErrorStreamEvents() returns http:SseEvent[] => [
    {data: string `{"id":"chatcmpl-err","choices":[{"index":0,"delta":{"content":"partial"}}]}`},
    {data: string `{"error":{"message":"${MOCK_PROVIDER_ERROR_MESSAGE}"}}`},
    {data: "[DONE]"}
];

// Mock intelligence service for Wso2ModelProvider tests.
// Returns a function-call response when the request contains `functions`, otherwise a plain text response.
// When the request has `stream: true`, responds with SSE chunks instead of a single JSON body; a message
// containing `TRIGGER_STREAM_ERROR` makes the streaming path fail with a 500, and one containing
// `TRIGGER_MALFORMED_CHUNK` streams an invalid chunk, and one containing `TRIGGER_PROVIDER_ERROR`
// streams a provider error payload. A message containing `TRIGGER_IMAGE_PROMPT` fails with a 500
// unless it also carries an image content part.
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
            string messagesText = messages is json[] ? messages.toString() : "";
            if messagesText.includes(TRIGGER_STREAM_ERROR) {
                return <http:InternalServerError>{body: {message: "simulated streaming failure"}};
            }
            if messagesText.includes(TRIGGER_IMAGE_PROMPT) && !messagesText.includes("\"image_url\"") {
                return <http:InternalServerError>{body: {message: "expected an image content part"}};
            }
            http:SseEvent[] events = messagesText.includes(TRIGGER_MALFORMED_CHUNK) ? mockMalformedStreamEvents()
                : messagesText.includes(TRIGGER_PROVIDER_ERROR) ? mockProviderErrorStreamEvents()
                : isFunctionCall ? mockFunctionCallStreamEvents() : mockTextStreamEvents();
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

// A chunk stream source over a fixed list of chunks that records whether it was closed.
class TrackingChunkIterator {
    private final ChatMessageChunk[] chunks;
    private int index = 0;
    private boolean closed = false;

    function init(ChatMessageChunk[] chunks) {
        self.chunks = chunks;
    }

    public isolated function next() returns record {|ChatMessageChunk value;|}? {
        lock {
            if self.index >= self.chunks.length() {
                return ();
            }
            ChatMessageChunk chunk = self.chunks[self.index];
            self.index += 1;
            return {value: chunk};
        }
    }

    public isolated function close() returns Error? {
        lock {
            self.closed = true;
        }
    }

    isolated function isClosed() returns boolean {
        lock {
            return self.closed;
        }
    }
}

// Opens a chunk stream over `sseSource` the same way `chatAsStream` does after the SSE connection opens.
function newChunkStream(MockSseEventIterator sseSource) returns [stream<ChatMessageChunk, Error?>, Wso2ChatStreamIterator] {
    Wso2ChatStreamIterator iterator = new (new stream<http:SseEvent, error?>(sseSource),
        observe:createChatSpan(WSO2_DEFAULT_MODEL));
    return [new stream<ChatMessageChunk, Error?>(iterator), iterator];
}

function collectChunks(stream<ChatMessageChunk, Error?> chunkStream) returns ChatMessageChunk[]|Error {
    return from ChatMessageChunk chunk in chunkStream
        select chunk;
}

function searchTools() returns ChatCompletionFunctions[] => [
    {
        name: "searchFunction",
        description: "Search for information",
        parameters: {
            'type: "object",
            properties: {query: {'type: "string"}}
        }
    }
];

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
    ChatAssistantMessage response = check provider->chat({role: USER, content: "Search for test"}, searchTools());
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
function testWso2ModelProviderChatAsStreamWithUserMessage() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    stream<ChatMessageChunk, Error?> chunkStream = check provider->chatAsStream({role: USER, content: "Hello"}, []);
    ChatMessageChunk[] chunks = check collectChunks(chunkStream);

    // The role-only opening delta, the keep-alive comment and the usage-only event are skipped.
    test:assertEquals(chunks.length(), 3);
    string content = "";
    foreach ChatMessageChunk chunk in chunks {
        test:assertEquals(chunk.role, ASSISTANT);
        test:assertEquals(chunk.id, MOCK_STREAM_TEXT_ID);
        test:assertTrue(chunk.toolCalls is (), "Expected no tool calls in a text stream");
        test:assertTrue(chunk.reasoning is (), "Expected no reasoning in a WSO2 stream");
        content += chunk.content ?: "";
    }
    test:assertEquals(content, MOCK_CHAT_TEXT_RESPONSE);
    test:assertEquals(chunks[0].content, "Hello! ");
    test:assertEquals(chunks[0].finishReason, ());
    test:assertEquals(chunks[2].content, ());
    test:assertEquals(chunks[2].finishReason, STOP);
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatAsStreamWithTools() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    stream<ChatMessageChunk, Error?> chunkStream =
        check provider->chatAsStream({role: USER, content: "Search for test"}, searchTools());
    ChatMessageChunk[] chunks = check collectChunks(chunkStream);

    // The role-only opening delta is skipped; three tool-call fragments and a finish chunk remain.
    test:assertEquals(chunks.length(), 4);
    ToolCallChunk[] fragments = [];
    foreach ChatMessageChunk chunk in chunks {
        test:assertEquals(chunk.role, ASSISTANT);
        test:assertEquals(chunk.id, MOCK_STREAM_TOOL_ID);
        test:assertEquals(chunk.content, ());
        ToolCallChunk[]? toolCalls = chunk.toolCalls;
        if toolCalls is ToolCallChunk[] {
            fragments.push(...toolCalls);
        }
    }
    test:assertEquals(fragments.length(), 3);

    // `name` is sent only on the first fragment; `arguments` are passed through as raw fragments.
    ToolCallChunk expectedFirst = {index: 0, name: "searchFunction", arguments: ""};
    test:assertEquals(fragments[0], expectedFirst);
    ToolCallChunk expectedSecond = {index: 0, arguments: "{\"query\":"};
    test:assertEquals(fragments[1], expectedSecond);
    ToolCallChunk expectedThird = {index: 0, arguments: "\"test\"}"};
    test:assertEquals(fragments[2], expectedThird);

    string arguments = "";
    foreach ToolCallChunk fragment in fragments {
        arguments += fragment.arguments ?: "";
    }
    map<json> parsedArguments = check arguments.fromJsonStringWithType();
    test:assertEquals(parsedArguments["query"], "test");

    test:assertEquals(chunks[3].toolCalls, ());
    test:assertEquals(chunks[3].finishReason, TOOL_CALLS);
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2FinishReasonMapping() {
    test:assertEquals(mapWso2FinishReason("stop"), STOP);
    test:assertEquals(mapWso2FinishReason("length"), LENGTH);
    test:assertEquals(mapWso2FinishReason("tool_calls"), TOOL_CALLS);
    test:assertEquals(mapWso2FinishReason("function_call"), TOOL_CALLS);
    test:assertEquals(mapWso2FinishReason("content_filter"), CONTENT_FILTER);
    test:assertEquals(mapWso2FinishReason("some_new_reason"), ());
    test:assertEquals(mapWso2FinishReason(()), ());
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2StreamChunkMapping() {
    // Events that carry nothing for the caller are skipped.
    test:assertEquals(mapWso2StreamChunk({id: "c1"}), ());
    test:assertEquals(mapWso2StreamChunk({id: "c1", choices: []}), ());
    test:assertEquals(mapWso2StreamChunk({id: "c1", choices: [{index: 0, delta: {"role": "assistant"}}]}), ());
    test:assertEquals(mapWso2StreamChunk({id: "c1", choices: [{index: 0, delta: {content: ""}}]}), ());

    // An unknown finish reason maps to `()` instead of failing the stream.
    test:assertEquals(mapWso2StreamChunk({id: "c1", choices: [{index: 0, delta: {}, finishReason: "new_reason"}]}), ());
    ChatMessageChunk expectedContent = {role: ASSISTANT, content: "Hi"};
    test:assertEquals(mapWso2StreamChunk({choices: [{delta: {content: "Hi"}, finishReason: "new_reason"}]}),
            expectedContent);

    ChatMessageChunk expectedLength = {id: "c1", role: ASSISTANT, finishReason: LENGTH};
    test:assertEquals(mapWso2StreamChunk({id: "c1", choices: [{index: 0, delta: {}, finishReason: "length"}]}),
            expectedLength);
    ChatMessageChunk expectedFiltered = {id: "c1", role: ASSISTANT, finishReason: CONTENT_FILTER};
    test:assertEquals(
            mapWso2StreamChunk({id: "c1", choices: [{index: 0, delta: {}, finishReason: "content_filter"}]}),
            expectedFiltered);
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatAsStreamHttpError() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    stream<ChatMessageChunk, Error?>|Error result =
        provider->chatAsStream({role: USER, content: TRIGGER_STREAM_ERROR}, []);
    test:assertTrue(result is LlmConnectionError, "Expected an `LlmConnectionError` for an HTTP error response");
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatAsStreamConnectionFailure() returns error? {
    Wso2ModelProvider provider = check new (UNREACHABLE_CHAT_URL, "test-token");
    stream<ChatMessageChunk, Error?>|Error result = provider->chatAsStream({role: USER, content: "Hello"}, []);
    test:assertTrue(result is LlmConnectionError, "Expected an `LlmConnectionError` when the model is unreachable");
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatAsStreamMalformedChunk() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    stream<ChatMessageChunk, Error?> chunkStream =
        check provider->chatAsStream({role: USER, content: TRIGGER_MALFORMED_CHUNK}, []);

    record {|ChatMessageChunk value;|}|Error? first = chunkStream.next();
    if first !is record {|ChatMessageChunk value;|} {
        test:assertFail("Expected the well-formed chunk before the malformed one");
    }
    test:assertEquals(first.value.content, "partial");

    record {|ChatMessageChunk value;|}|Error? second = chunkStream.next();
    test:assertTrue(second is LlmInvalidResponseError, "Expected an `LlmInvalidResponseError` for a malformed chunk");
    test:assertTrue(chunkStream.next() is (), "Expected the stream to end after an error");
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatAsStreamProviderError() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    stream<ChatMessageChunk, Error?> chunkStream =
        check provider->chatAsStream({role: USER, content: TRIGGER_PROVIDER_ERROR}, []);

    record {|ChatMessageChunk value;|}|Error? first = chunkStream.next();
    if first !is record {|ChatMessageChunk value;|} {
        test:assertFail("Expected the well-formed chunk before the provider error");
    }
    test:assertEquals(first.value.content, "partial");

    record {|ChatMessageChunk value;|}|Error? second = chunkStream.next();
    if second !is LlmInvalidResponseError {
        test:assertFail("Expected an `LlmInvalidResponseError` for a provider error payload");
    }
    test:assertEquals(second.message(), MOCK_PROVIDER_ERROR_MESSAGE);
    test:assertTrue(chunkStream.next() is (), "Expected the stream to end after an error");
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatAsStreamCloseAfterDone() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    stream<ChatMessageChunk, Error?> chunkStream = check provider->chatAsStream({role: USER, content: "Hello"}, []);
    _ = check collectChunks(chunkStream);
    // The SSE stream is already closed on `[DONE]`; closing again must be a no-op.
    check chunkStream.close();
    check chunkStream.close();
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderGenerateAsStream() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    stream<string, Error?> textStream = check provider->generateAsStream(`Hello`);
    string[] fragments = check from string fragment in textStream
        select fragment;
    // Only the content fragments surface; the role-only, finish-only and usage-only events do not.
    test:assertEquals(fragments, ["Hello! ", "How can I help you today?"]);
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderGenerateAsStreamHttpError() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    stream<string, Error?>|Error result = provider->generateAsStream(`Please ${TRIGGER_STREAM_ERROR}`);
    test:assertTrue(result is LlmConnectionError, "Expected an `LlmConnectionError` for an HTTP error response");
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testGenerateAsStreamYieldsOnlyContent() returns error? {
    ChatMessageChunk[] mixedChunks = [
        {role: ASSISTANT, reasoning: "Thinking about a greeting."},
        {role: ASSISTANT, content: "Hello"},
        {role: ASSISTANT, content: ""},
        {role: ASSISTANT, toolCalls: [{index: 0, id: "call-1", name: "searchFunction", arguments: "{}"}]},
        {role: ASSISTANT, content: " there"},
        {role: ASSISTANT, finishReason: STOP}
    ];
    stream<ChatMessageChunk, Error?> chunkStream = new (new TrackingChunkIterator(mixedChunks.clone()));
    stream<string, Error?> textStream = new (new TextContentIterator(chunkStream));
    string[] fragments = check from string fragment in textStream
        select fragment;
    test:assertEquals(fragments, ["Hello", " there"]);

    // Closing the text stream early closes the underlying chunk stream.
    TrackingChunkIterator earlySource = new (mixedChunks.clone());
    stream<ChatMessageChunk, Error?> earlyChunkStream = new (earlySource);
    stream<string, Error?> earlyTextStream = new (new TextContentIterator(earlyChunkStream));
    record {|string value;|}|Error? first = earlyTextStream.next();
    if first !is record {|string value;|} {
        test:assertFail("Expected a text fragment");
    }
    test:assertEquals(first.value, "Hello");
    check earlyTextStream.close();
    test:assertTrue(earlySource.isClosed(), "Expected closing the text stream to close the chunk stream");
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ChatStreamEarlyClose() returns error? {
    MockSseEventIterator sseSource = new (mockTextStreamEvents());
    [stream<ChatMessageChunk, Error?>, Wso2ChatStreamIterator] [chunkStream, iterator] = newChunkStream(sseSource);

    record {|ChatMessageChunk value;|}|Error? first = chunkStream.next();
    if first !is record {|ChatMessageChunk value;|} {
        test:assertFail("Expected a chunk before closing the stream");
    }
    test:assertEquals(first.value.content, "Hello! ");

    check chunkStream.close();
    test:assertTrue(sseSource.isClosed(), "Expected closing the stream to close the SSE stream");
    test:assertTrue(chunkStream.next() is (), "Expected no more chunks after the stream is closed");
    // Only the output received before the early close is recorded.
    test:assertEquals(iterator.outputMessage(), {role: ASSISTANT, content: "Hello! ", toolCalls: ()});
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ChatStreamWithoutDone() returns error? {
    // A stream that ends after a finish reason but without `[DONE]` completes normally.
    http:SseEvent[] finishedEvents = mockTextStreamEvents();
    _ = finishedEvents.pop();
    MockSseEventIterator finishedSource = new (finishedEvents);
    [stream<ChatMessageChunk, Error?>, Wso2ChatStreamIterator] [finishedStream, _] = newChunkStream(finishedSource);
    ChatMessageChunk[] chunks = check collectChunks(finishedStream);
    test:assertEquals(chunks.length(), 3);
    test:assertTrue(finishedSource.isClosed(), "Expected the SSE stream to be closed when it runs out");

    // A stream that ends with neither `[DONE]` nor a finish reason was cut off.
    MockSseEventIterator cutOffSource = new ([
        {data: string `{"id":"chatcmpl-cut","choices":[{"index":0,"delta":{"content":"partial"}}]}`}
    ]);
    [stream<ChatMessageChunk, Error?>, Wso2ChatStreamIterator] [cutOffStream, _] = newChunkStream(cutOffSource);
    record {|ChatMessageChunk value;|}|Error? first = cutOffStream.next();
    if first !is record {|ChatMessageChunk value;|} {
        test:assertFail("Expected the chunk received before the stream was cut off");
    }
    test:assertEquals(first.value.content, "partial");
    test:assertTrue(cutOffStream.next() is LlmConnectionError,
            "Expected an `LlmConnectionError` for a stream that ends before it completes");
    test:assertTrue(cutOffStream.next() is (), "Expected the stream to end after an error");
    test:assertTrue(cutOffSource.isClosed(), "Expected the SSE stream to be closed after an error");
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ChatStreamDroppedConnection() returns error? {
    MockSseEventIterator sseSource = new ([
        {data: string `{"id":"chatcmpl-drop","choices":[{"index":0,"delta":{"content":"partial"}}]}`}
    ], dropConnection = true);
    [stream<ChatMessageChunk, Error?>, Wso2ChatStreamIterator] [chunkStream, _] = newChunkStream(sseSource);

    record {|ChatMessageChunk value;|}|Error? first = chunkStream.next();
    if first !is record {|ChatMessageChunk value;|} {
        test:assertFail("Expected the chunk received before the connection dropped");
    }
    test:assertEquals(first.value.content, "partial");
    test:assertTrue(chunkStream.next() is LlmConnectionError,
            "Expected an `LlmConnectionError` when the connection drops");
    test:assertTrue(chunkStream.next() is (), "Expected the stream to end after an error");
    test:assertTrue(sseSource.isClosed(), "Expected the SSE stream to be closed after an error");
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ChatStreamOutputMessage() returns error? {
    [stream<ChatMessageChunk, Error?>, Wso2ChatStreamIterator] [textStream, textIterator] =
        newChunkStream(new (mockTextStreamEvents()));
    _ = check collectChunks(textStream);
    test:assertEquals(textIterator.outputMessage(), {role: ASSISTANT, content: MOCK_CHAT_TEXT_RESPONSE, toolCalls: ()});

    // Tool-call fragments are joined into a single function call with parsed arguments.
    [stream<ChatMessageChunk, Error?>, Wso2ChatStreamIterator] [toolStream, toolIterator] =
        newChunkStream(new (mockFunctionCallStreamEvents()));
    _ = check collectChunks(toolStream);
    ChatAssistantMessage expected = {
        role: ASSISTANT,
        content: (),
        toolCalls: [{name: "searchFunction", arguments: {"query": "test"}}]
    };
    test:assertEquals(toolIterator.outputMessage(), expected);

    // Nothing is recorded when no content or tool call was received.
    [stream<ChatMessageChunk, Error?>, Wso2ChatStreamIterator] [emptyStream, emptyIterator] =
        newChunkStream(new ([{data: "[DONE]"}]));
    _ = check collectChunks(emptyStream);
    test:assertEquals(emptyIterator.outputMessage(), ());
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderGenerateAsStreamWithImage() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");

    ImageDocument urlImage = {content: MOCK_IMAGE_URL};
    stream<string, Error?> urlStream = check provider->generateAsStream(`${TRIGGER_IMAGE_PROMPT} ${urlImage}`);
    string[] urlFragments = check from string fragment in urlStream
        select fragment;
    test:assertEquals(urlFragments, ["Hello! ", "How can I help you today?"]);

    ImageDocument binaryImage = {content: [137, 80, 78, 71], metadata: {mimeType: "image/png"}};
    stream<string, Error?> binaryStream = check provider->generateAsStream(`${TRIGGER_IMAGE_PROMPT} ${binaryImage}`);
    string[] binaryFragments = check from string fragment in binaryStream
        select fragment;
    test:assertEquals(binaryFragments, ["Hello! ", "How can I help you today?"]);
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderGenerateAsStreamWithDocuments() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");

    TextDocument textDocument = {content: "Streaming sends partial responses."};
    stream<string, Error?> textStream = check provider->generateAsStream(`Summarize ${textDocument}`);
    string[] fragments = check from string fragment in textStream
        select fragment;
    test:assertEquals(fragments, ["Hello! ", "How can I help you today?"]);

    // Only text and image documents are supported; others fail before the request is sent.
    AudioDocument audioDocument = {content: "https://example.com/talk.mp3"};
    stream<string, Error?>|Error result = provider->generateAsStream(`Transcribe ${audioDocument}`);
    test:assertTrue(result is Error, "Expected an error for an unsupported document type");
}
