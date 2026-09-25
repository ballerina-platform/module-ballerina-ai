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

import ballerina/jballerina.java;
import ballerina/test;

isolated function getWeatherMock(string city) returns string => string `31C and sunny in ${city}`;

isolated function getTimeMock(string city) returns string => string `10:00 in ${city}`;

final ToolConfig streamWeatherTool = {
    name: "getWeather",
    description: "Gets the current weather of a city",
    parameters: {properties: {city: {'type: STRING}}},
    caller: getWeatherMock
};

final ToolConfig streamTimeTool = {
    name: "getTime",
    description: "Gets the current time of a city",
    parameters: {properties: {city: {'type: STRING}}},
    caller: getTimeMock
};

const STREAM_PRELUDE = "Let me check.";
const STREAM_FINAL_ANSWER = "It is 31C and sunny in Colombo at 10:00 in Colombo.";

// On the first turn, says it will look things up and proposes two tool calls in parallel; once
// both tool results are in the history, answers with them.
public isolated client class WeatherMockLLM {
    *ModelProvider;

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [],
            string? stop = ()) returns ChatAssistantMessage|Error {
        ChatMessage[] msgs;
        if messages is ChatUserMessage {
            msgs = [messages];
        } else {
            msgs = messages;
        }
        string[] results = [];
        foreach ChatMessage message in msgs {
            if message is ChatFunctionMessage {
                results.push(message.content ?: "");
            }
        }
        if results.length() < 2 {
            return {
                role: ASSISTANT,
                content: STREAM_PRELUDE,
                toolCalls: [
                    {name: "getWeather", arguments: {city: "Colombo"}, id: "call-weather"},
                    {name: "getTime", arguments: {city: "Colombo"}, id: "call-time"}
                ]
            };
        }
        return {role: ASSISTANT, content: string `It is ${results[0]} at ${results[1]}.`};
    }

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.lib.ai.MockGenerator"
    } external;

    isolated remote function chatAsStream(ChatMessage[]|ChatUserMessage messages,
            ChatCompletionFunctions[] tools = [], string? stop = ()) returns stream<ChatMessageChunk, Error?>|Error {
        return error Error("chatAsStream not implemented in WeatherMockLLM");
    }

    isolated remote function generateAsStream(Prompt prompt) returns stream<string, Error?>|Error {
        return error Error("generateAsStream not implemented");
    }
}

// Adds streaming to any non-streaming mock: `chatAsStream` streams the wrapped model's `chat`
// response the way a real provider does - content in small fragments, and each tool call as a
// first fragment carrying its id and name followed by argument fragments, interleaved across
// parallel calls and correlated by `index`.
public isolated client class StreamingMockLLM {
    *ModelProvider;
    private final ModelProvider inner;

    isolated function init(ModelProvider inner) {
        self.inner = inner;
    }

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [],
            string? stop = ()) returns ChatAssistantMessage|Error {
        return self.inner->chat(messages, tools, stop);
    }

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.lib.ai.MockGenerator"
    } external;

    isolated remote function chatAsStream(ChatMessage[]|ChatUserMessage messages,
            ChatCompletionFunctions[] tools = [], string? stop = ()) returns stream<ChatMessageChunk, Error?>|Error {
        ChatAssistantMessage response = check self.inner->chat(messages, tools, stop);
        return toChunks(response).toStream();
    }

    isolated remote function generateAsStream(Prompt prompt) returns stream<string, Error?>|Error {
        return error Error("generateAsStream not implemented");
    }
}

// Streams a tool call whose argument fragments never form valid JSON.
public isolated client class MalformedArgumentsStreamMockLLM {
    *ModelProvider;

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [],
            string? stop = ()) returns ChatAssistantMessage|Error {
        return error Error("chat not implemented in MalformedArgumentsStreamMockLLM");
    }

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.lib.ai.MockGenerator"
    } external;

    isolated remote function chatAsStream(ChatMessage[]|ChatUserMessage messages,
            ChatCompletionFunctions[] tools = [], string? stop = ()) returns stream<ChatMessageChunk, Error?>|Error {
        ChatMessageChunk[] chunks = [
            {role: ASSISTANT, toolCalls: [{index: 0, id: "call-1", name: "getWeather"}]},
            {role: ASSISTANT, toolCalls: [{index: 0, arguments: "{\"city\": "}]},
            {role: ASSISTANT, finishReason: TOOL_CALLS}
        ];
        return chunks.toStream();
    }

    isolated remote function generateAsStream(Prompt prompt) returns stream<string, Error?>|Error {
        return error Error("generateAsStream not implemented");
    }
}

isolated function toChunks(ChatAssistantMessage message) returns ChatMessageChunk[] {
    ChatMessageChunk[] chunks = [];
    string? content = message.content;
    if content is string {
        int i = 0;
        while i < content.length() {
            int end = int:min(i + 4, content.length());
            chunks.push({role: ASSISTANT, content: content.substring(i, end)});
            i = end;
        }
    }
    FunctionCall[]? toolCalls = message.toolCalls;
    if toolCalls is FunctionCall[] {
        foreach int index in 0 ..< toolCalls.length() {
            ToolCallChunk first = {index, name: toolCalls[index].name};
            string? id = toolCalls[index].id;
            if id is string {
                first.id = id;
            }
            chunks.push({role: ASSISTANT, toolCalls: [first]});
        }
        string[] arguments = from FunctionCall call in toolCalls select (call.arguments ?: {}).toJsonString();
        int position = 0;
        boolean pending = true;
        while pending {
            pending = false;
            foreach int index in 0 ..< arguments.length() {
                string args = arguments[index];
                if position < args.length() {
                    int end = int:min(position + 5, args.length());
                    chunks.push({role: ASSISTANT, toolCalls: [{index, arguments: args.substring(position, end)}]});
                    pending = true;
                }
            }
            position += 5;
        }
    }
    chunks.push({role: ASSISTANT, finishReason: toolCalls is FunctionCall[] ? TOOL_CALLS : STOP});
    return chunks;
}

function newWeatherAgent() returns Agent|error => new ({
    systemPrompt: {role: "Weather Agent", instructions: "Answer weather questions using the tools"},
    model: new StreamingMockLLM(new WeatherMockLLM()),
    tools: [streamWeatherTool, streamTimeTool]
});

function collectEvents(stream<AgentEvent, Error?> events) returns [AgentEvent[], Error?] {
    AgentEvent[] collected = [];
    while true {
        record {|AgentEvent value;|}|Error? next = events.next();
        if next is () || next is Error {
            return [collected, next];
        }
        collected.push(next.value);
    }
}

function collectText(stream<string, Error?> text) returns [string, Error?] {
    string collected = "";
    while true {
        record {|string value;|}|Error? next = text.next();
        if next is () || next is Error {
            return [collected, next];
        }
        collected += next.value;
    }
}

function joinContent(AgentEvent[] events) returns string {
    string content = "";
    foreach AgentEvent event in events {
        if event is ContentDeltaEvent {
            content += event.content;
        }
    }
    return content;
}

@test:Config
function testStreamingEventsWithParallelToolCalls() returns error? {
    Agent agent = check newWeatherAgent();
    stream<AgentEvent, Error?> events = check agent.run("Weather in Colombo?", "stream-events-session",
        enableStreaming = true);
    var [collected, err] = collectEvents(events);
    test:assertEquals(err, ());

    ToolCallEvent[] toolCalls = [];
    ToolResultEvent[] toolResults = [];
    foreach AgentEvent event in collected {
        if event is ToolCallEvent {
            toolCalls.push(event);
        } else if event is ToolResultEvent {
            toolResults.push(event);
        }
    }
    test:assertEquals(toolCalls.length(), 2);
    test:assertEquals(toolCalls[0].name, "getWeather");
    test:assertEquals(toolCalls[0].arguments, {city: "Colombo"});
    test:assertEquals(toolCalls[0].id, "call-weather");
    test:assertEquals(toolCalls[0].iteration, 1);
    test:assertEquals(toolCalls[1].name, "getTime");
    test:assertEquals(toolCalls[1].arguments, {city: "Colombo"});

    test:assertEquals(toolResults.length(), 2);
    test:assertEquals(toolResults[0].name, "getWeather");
    test:assertEquals(toolResults[0].output, "31C and sunny in Colombo");
    test:assertFalse(toolResults[0].isError);
    test:assertEquals(toolResults[1].output, "10:00 in Colombo");

    // Text streamed before the tool calls is emitted too, followed by the final answer's fragments.
    test:assertEquals(joinContent(collected), STREAM_PRELUDE + STREAM_FINAL_ANSWER);
    AgentEvent last = collected[collected.length() - 1];
    test:assertTrue(last is AgentCompletedEvent);
    if last is AgentCompletedEvent {
        test:assertEquals(last.answer, STREAM_FINAL_ANSWER);
    }
}

@test:Config
function testStreamingText() returns error? {
    Agent agent = check newWeatherAgent();
    stream<string, Error?> text = check agent.run("Weather in Colombo?", "stream-text-session", enableStreaming = true);
    var [collected, err] = collectText(text);
    test:assertEquals(err, ());
    test:assertEquals(collected, STREAM_PRELUDE + STREAM_FINAL_ANSWER);
}

@test:Config
function testStreamedRunWritesSameMemoryAsRun() returns error? {
    Agent agent = check newWeatherAgent();
    string answer = check agent.run("Weather in Colombo?", "memory-run-session");
    test:assertEquals(answer, STREAM_FINAL_ANSWER);

    stream<AgentEvent, Error?> events = check agent.run("Weather in Colombo?", "memory-stream-session",
        enableStreaming = true);
    var [_, err] = collectEvents(events);
    test:assertEquals(err, ());

    ChatMessage[] runHistory = check agent.memory.get("memory-run-session");
    ChatMessage[] streamHistory = check agent.memory.get("memory-stream-session");
    test:assertEquals(streamHistory.toString(), runHistory.toString());
}

@test:Config
function testStreamingRejectsNonStreamType() returns error? {
    Agent agent = check newWeatherAgent();
    string|Error result = agent.run("Weather in Colombo?", "stream-type-session", enableStreaming = true);
    test:assertTrue(result is Error);
    if result is Error {
        test:assertTrue(result.message().startsWith("Streaming is only supported for"), result.message());
    }
}

@test:Config
function testStreamTypeRequiresStreamingFlag() returns error? {
    Agent agent = check newWeatherAgent();
    stream<AgentEvent, Error?>|Error result = agent.run("Weather in Colombo?", "stream-flag-session");
    test:assertTrue(result is Error);
    if result is Error {
        test:assertTrue(result.message().includes("enableStreaming = true"), result.message());
    }
}

@test:Config
function testStreamingHumanInTheLoopPauseAndResume() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new StreamingMockLLM(new HitlMockLLM()),
        tools: [hitlRefundTool]
    });
    string sessionId = "stream-hitl-session";
    stream<AgentEvent, Error?> events = check agent.run("Refund order ORD-1", sessionId, enableStreaming = true);
    var [collected, err] = collectEvents(events);
    test:assertEquals(err, ());
    AgentEvent last = collected[collected.length() - 1];
    if last !is ApprovalRequiredEvent {
        test:assertFail("Expected the stream to end with an ApprovalRequiredEvent");
    }
    test:assertEquals(last.requests.length(), 1);
    test:assertEquals(last.requests[0].toolName, "issueRefund");
    test:assertEquals(last.requests[0].arguments, {"orderId": "ORD-1", "amount": 50});

    Resume resume = {decisions: {[last.requests[0].id]: {decision: APPROVE}}};
    stream<AgentEvent, Error?> resumed = check agent.run(resume, sessionId, enableStreaming = true);
    var [resumedEvents, resumeErr] = collectEvents(resumed);
    test:assertEquals(resumeErr, ());
    AgentEvent first = resumedEvents[0];
    if first !is ToolResultEvent {
        test:assertFail("Expected the resumed stream to start with the approved call's result");
    }
    test:assertEquals(first.name, "issueRefund");
    test:assertEquals(first.output, "Refunded 50.0 for ORD-1");
    AgentEvent completed = resumedEvents[resumedEvents.length() - 1];
    if completed !is AgentCompletedEvent {
        test:assertFail("Expected the resumed stream to end with an AgentCompletedEvent");
    }
    test:assertTrue(completed.answer.includes("Refunded 50.0 for ORD-1"), completed.answer);
}

@test:Config
function testStreamingTextPauseEndsWithApprovalRequiredError() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new StreamingMockLLM(new HitlMockLLM()),
        tools: [hitlRefundTool]
    });
    stream<string, Error?> text = check agent.run("Refund order ORD-1", "stream-text-hitl-session", enableStreaming = true);
    var [_, err] = collectText(text);
    test:assertTrue(err is ApprovalRequiredError);
}

@test:Config
function testStreamingPendingApprovalBlocksNewRun() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new StreamingMockLLM(new HitlMockLLM()),
        tools: [hitlRefundTool]
    });
    string sessionId = "stream-hitl-guard-session";
    string|Error paused = agent.run("Refund order ORD-1", sessionId);
    test:assertTrue(paused is ApprovalRequiredError);

    stream<AgentEvent, Error?> events = check agent.run("Something else", sessionId, enableStreaming = true);
    var [collected, err] = collectEvents(events);
    test:assertEquals(err, ());
    test:assertEquals(collected.length(), 1);
    test:assertTrue(collected[0] is ApprovalRequiredEvent);
}

@test:Config
function testStreamingMalformedToolArguments() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Weather Agent", instructions: "Answer weather questions"},
        model: new MalformedArgumentsStreamMockLLM(),
        tools: [streamWeatherTool]
    });
    stream<AgentEvent, Error?> events = check agent.run("Weather?", "stream-malformed-session", enableStreaming = true);
    var [_, err] = collectEvents(events);
    // As with a non-streamed run, an LLM failure ends the run with the failed step attached.
    if err !is Error {
        test:assertFail("Expected the stream to end with an error");
    }
    test:assertEquals(err.message(), "Unable to obtain valid answer from the agent");
    anydata|readonly steps = err.detail()["steps"];
    test:assertTrue(steps is readonly & (ExecutionResult|ExecutionError|Error)[]);
    if steps is readonly & (ExecutionResult|ExecutionError|Error)[] {
        test:assertTrue(steps[0] is LlmInvalidGenerationError);
    }
}

@test:Config
function testStreamingMaxIterations() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Search forever"},
        model: new StreamingMockLLM(new NeverAnsweringMockLLM()),
        tools: [searchTool],
        maxIter: 2
    });
    stream<AgentEvent, Error?> events = check agent.run("Who?", "stream-max-iter-session", enableStreaming = true);
    var [collected, err] = collectEvents(events);
    test:assertTrue(err is MaxIterationExceededError);
    int toolCallCount = 0;
    foreach AgentEvent event in collected {
        if event is ToolCallEvent {
            toolCallCount += 1;
        }
    }
    test:assertEquals(toolCallCount, 2);
}

@test:Config
function testClosingStreamEarlyDoesNotWriteMemory() returns error? {
    Agent agent = check newWeatherAgent();
    string sessionId = "stream-close-session";
    stream<AgentEvent, Error?> events = check agent.run("Weather in Colombo?", sessionId, enableStreaming = true);
    record {|AgentEvent value;|}|Error? first = events.next();
    test:assertTrue(first is record {|AgentEvent value;|});
    check events.close();

    ChatMessage[] history = check agent.memory.get(sessionId);
    test:assertEquals(history.length(), 0);
    record {|AgentEvent value;|}|Error? afterClose = events.next();
    test:assertEquals(afterClose, ());
}

@test:Config
function testClosingUnstartedResumeStreamKeepsPendingApproval() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new StreamingMockLLM(new HitlMockLLM()),
        tools: [hitlRefundTool]
    });
    string sessionId = "stream-close-resume-session";
    string|Error paused = agent.run("Refund order ORD-1", sessionId);
    if paused !is ApprovalRequiredError {
        test:assertFail("Expected the run to pause for approval");
    }
    Resume resume = singleResume(paused, {decision: APPROVE});
    stream<AgentEvent, Error?> resumed = check agent.run(resume, sessionId, enableStreaming = true);
    check resumed.close();

    // Nothing ran, so the pending approval was restored and can still be resumed.
    string|Error answer = agent.run(resume, sessionId);
    test:assertTrue(answer is string);
    if answer is string {
        test:assertTrue(answer.includes("Refunded 50.0 for ORD-1"), answer);
    }
}
