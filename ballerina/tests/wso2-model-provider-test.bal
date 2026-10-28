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
const MOCK_ECHO_TOOLS_PROMPT = "ECHO_TOOLS";
const MOCK_MALFORMED_ARGS_PROMPT = "MALFORMED_ARGS";

// Mock intelligence service for Wso2ModelProvider tests.
// Echoes the request messages back as the content when the last message is a tool result, echoes the
// request `tools` or returns malformed tool call arguments for the matching prompts, returns parallel
// tool calls when the request contains `tools`, and otherwise returns a plain text response.
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
        if payload.functions is json || payload.function_call is json {
            return error("legacy `functions` API must not be used");
        }
        json[] messages = check payload.messages.ensureType();
        json lastMessage = messages.length() > 0 ? messages[messages.length() - 1] : ();
        if lastMessage is map<json> && lastMessage["role"] == "tool" {
            return getMockTextResponse(messages.toJsonString());
        }
        if lastMessage is map<json> && lastMessage["content"] == MOCK_ECHO_TOOLS_PROMPT {
            return getMockTextResponse((check payload.tools).toJsonString());
        }
        if lastMessage is map<json> && lastMessage["content"] == MOCK_MALFORMED_ARGS_PROMPT {
            return getMockToolCallsResponse([
                {id: "call_bad", 'type: "function", 'function: {name: "searchFunction", arguments: "{not json"}}
            ]);
        }
        json|error tools = payload.tools;
        if tools is json[] && tools.length() > 0 {
            foreach json tool in tools {
                if check tool.'type != "function" || check tool.'function.name !is string {
                    return error("invalid tool definition: " + tool.toJsonString());
                }
            }
            return getMockToolCallsResponse([
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
            ]);
        }
        return getMockTextResponse(MOCK_CHAT_TEXT_RESPONSE);
    }
}

isolated function getMockToolCallsResponse(json[] toolCalls) returns json => {
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
                tool_calls: toolCalls
            },
            finish_reason: "tool_calls"
        }
    ]
};

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
    ]
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
function testWso2ModelProviderChatWithoutTools() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    ChatAssistantMessage response = check provider->chat({role: USER, content: "Hello"});
    test:assertEquals(response.role, ASSISTANT);
    test:assertEquals(response.content, MOCK_CHAT_TEXT_RESPONSE);
    test:assertTrue(response.toolCalls is (), "Expected no tool calls when no tools are given");
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

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatUsesUniqueFallbackIdsWhenIdsAreMissing() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    ChatMessage[] messages = [
        {role: USER, content: "Search for test and examples"},
        {
            role: ASSISTANT,
            toolCalls: [
                {name: "searchFunction", arguments: {query: "test"}},
                {name: "searchFunction", arguments: {query: "examples"}}
            ]
        },
        {role: FUNCTION, name: "searchFunction", content: "test result"},
        {role: FUNCTION, name: "searchFunction", content: "example result"}
    ];
    ChatAssistantMessage response = check provider->chat(messages, []);
    string? content = response.content;
    if content is () {
        test:assertFail("Expected the mock to echo the request messages");
    }
    json[] sentMessages = check (check content.fromJsonString()).ensureType();
    test:assertEquals(sentMessages[1], {
        role: "assistant",
        tool_calls: [
            {
                id: "searchFunction-0",
                'type: "function",
                'function: {name: "searchFunction", arguments: "{\"query\":\"test\"}"}
            },
            {
                id: "searchFunction-1",
                'type: "function",
                'function: {name: "searchFunction", arguments: "{\"query\":\"examples\"}"}
            }
        ]
    });
    test:assertEquals(sentMessages[2], {role: "tool", tool_call_id: "searchFunction-0", content: "test result"});
    test:assertEquals(sentMessages[3], {role: "tool", tool_call_id: "searchFunction-1", content: "example result"});
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatSendsToolsInToolsApiFormat() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    ChatCompletionFunctions[] tools = [
        {
            name: "searchFunction",
            description: "Search for information",
            parameters: {'type: "object", properties: {query: {'type: "string"}}}
        },
        {name: "getTime", description: "Get the current time"}
    ];
    ChatAssistantMessage response = check provider->chat({role: USER, content: MOCK_ECHO_TOOLS_PROMPT}, tools);
    string? content = response.content;
    if content is () {
        test:assertFail("Expected the mock to echo the request tools");
    }
    test:assertEquals(check content.fromJsonString(), [
        {
            'type: "function",
            'function: {
                name: "searchFunction",
                description: "Search for information",
                parameters: {'type: "object", properties: {query: {'type: "string"}}}
            }
        },
        {
            'type: "function",
            'function: {
                name: "getTime",
                description: "Get the current time",
                parameters: {'type: "object", properties: {}}
            }
        }
    ]);
}

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderChatWithMalformedToolCallArguments() returns error? {
    Wso2ModelProvider provider = check new (MOCK_CHAT_URL, "test-token");
    ChatCompletionFunctions[] tools = [
        {name: "searchFunction", description: "Search for information"}
    ];
    ChatAssistantMessage|Error response = provider->chat({role: USER, content: MOCK_MALFORMED_ARGS_PROMPT}, tools);
    if response is ChatAssistantMessage {
        test:assertFail("Expected an error for malformed tool call arguments");
    }
    test:assertTrue(response is LlmError);
    test:assertEquals(response.message(), "Invalid or malformed arguments received in function call response.");
}

const int MOCK_AGENT_CHAT_PORT = 9086;
const MOCK_AGENT_CHAT_URL = "http://localhost:9086";

// Mock intelligence service that drives an agent through the scenario in
// https://github.com/wso2/product-integrator/issues/2802. The first turn proposes three parallel tool
// calls; once tool results are present, it answers with each `tool_call_id` and its result, after
// checking that every tool result responds to a tool call the assistant made.
service on new http:Listener(MOCK_AGENT_CHAT_PORT) {

    resource function post chat/completions(@http:Payload json payload) returns json|error {
        if payload.functions is json || payload.function_call is json {
            return error("legacy `functions` API must not be used");
        }
        json[] messages = check payload.messages.ensureType();
        string[] toolCallIds = [];
        string[] toolResults = [];
        foreach json message in messages {
            if message !is map<json> {
                continue;
            }
            json toolCalls = message["tool_calls"];
            if message["role"] == "assistant" && toolCalls is json[] {
                foreach json toolCall in toolCalls {
                    string toolCallId = check toolCall.id.ensureType();
                    toolCallIds.push(toolCallId);
                }
            }
            if message["role"] == "tool" {
                string toolCallId = check message.tool_call_id.ensureType();
                string content = check message.content.ensureType();
                if toolCallIds.indexOf(toolCallId) is () {
                    return error("tool result for unknown tool call: " + toolCallId);
                }
                toolResults.push(string `${toolCallId}=${content}`);
            }
        }
        if toolResults.length() > 0 {
            return getMockTextResponse(string:'join("\n", ...toolResults));
        }
        return getMockToolCallsResponse([
            {
                id: "call_delete",
                'type: "function",
                'function: {name: "deleteFile", arguments: "{\"path\":\"/tmp/old-report.txt\"}"}
            },
            {
                id: "call_alice",
                'type: "function",
                'function: {name: "transferFunds", arguments: "{\"amount\":5000,\"recipient\":\"Alice\"}"}
            },
            {
                id: "call_bob",
                'type: "function",
                'function: {name: "transferFunds", arguments: "{\"amount\":50,\"recipient\":\"Bob\"}"}
            }
        ]);
    }
}

isolated function deleteFileMock(string path) returns string => string `File ${path} deleted.`;

isolated function transferFundsMock(decimal amount, string recipient) returns string =>
    string `Transferred ${amount} to ${recipient}.`;

isolated function transferNeedsApproval(decimal amount, string recipient) returns boolean {
    _ = recipient;
    return amount > 1000d;
}

function newWso2ModelProviderHitlAgent() returns Agent|error =>
    new ({
        systemPrompt: {role: "Operations Assistant", instructions: "Run the requested operations."},
        model: check new Wso2ModelProvider(MOCK_AGENT_CHAT_URL, "test-token"),
        tools: [
            {
                name: "deleteFile",
                description: "Deletes the file at the given path.",
                parameters: {properties: {path: {'type: STRING}}},
                caller: deleteFileMock,
                requiresApproval: true
            },
            {
                name: "transferFunds",
                description: "Transfers the given amount of money to a recipient.",
                parameters: {properties: {amount: {'type: NUMBER}, recipient: {'type: STRING}}},
                caller: transferFundsMock,
                requiresApproval: transferNeedsApproval
            }
        ]
    });

@test:Config {
    groups: ["wso2-model-provider"]
}
function testWso2ModelProviderAgentSurfacesParallelGatedCallsTogether() returns error? {
    Agent agent = check newWso2ModelProviderHitlAgent();
    string sessionId = "wso2-provider-parallel-hitl-session";
    string|Error result = agent.run(
        "Delete the file /tmp/old-report.txt, transfer 5000 to Alice, and transfer 50 to Bob.", sessionId);
    if result !is ApprovalRequiredError {
        test:assertFail("Expected an approval pause, found: " + (result is Error ? result.message() : result));
    }

    // Both gated calls from the single model response are surfaced together in one pause.
    ApprovalRequest[] requests = result.detail().requests;
    test:assertEquals(requests.length(), 2);
    test:assertEquals(requests[0].toolName, "deleteFile");
    test:assertEquals(requests[0].arguments, {path: "/tmp/old-report.txt"});
    test:assertEquals(requests[0].toolCallId, "call_delete");
    test:assertEquals(requests[0].batchIndex, 0);
    test:assertEquals(requests[1].toolName, "transferFunds");
    test:assertEquals(requests[1].arguments, {amount: 5000, recipient: "Alice"});
    test:assertEquals(requests[1].toolCallId, "call_alice");
    test:assertEquals(requests[1].batchIndex, 1);

    map<HumanDecision> & readonly decisions = {
        [requests[0].id]: {outcome: APPROVE},
        [requests[1].id]: {outcome: REJECT, reason: "Amount exceeds the daily limit."}
    };
    string|Error resumed = agent.run(<Resume>{decisions}, sessionId);
    if resumed !is string {
        test:assertFail("Expected a final answer, found: " + resumed.message());
    }
    // Every result is sent back against the id of the tool call it responds to. The batch runs in
    // parallel, so results are keyed by id rather than read in batch order.
    map<string> results = {};
    foreach string line in re `\n`.split(resumed) {
        string[] parts = re `=`.split(line);
        results[parts[0]] = line.substring(parts[0].length() + 1);
    }
    test:assertEquals(results.keys().sort(), ["call_alice", "call_bob", "call_delete"]);
    test:assertEquals(results["call_delete"], "File /tmp/old-report.txt deleted.");
    string aliceResult = results.get("call_alice");
    test:assertTrue(aliceResult.includes("rejected"), aliceResult);
    test:assertTrue(aliceResult.includes("Amount exceeds the daily limit."), aliceResult);
    string bobResult = results.get("call_bob");
    test:assertTrue(bobResult.startsWith("Transferred 50"), bobResult);
    test:assertTrue(bobResult.endsWith("to Bob."), bobResult);
}
