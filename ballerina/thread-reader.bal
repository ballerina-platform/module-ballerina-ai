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

import ballerina/io;
import ballerina/time;

# Loads conversation threads from a evaluation dataset JSON file.
#
# Parses an evaluation set JSON file containing conversation threads with agent traces.
# The JSON must contain a root object with an array of threads, where each thread represents
# a conversation thread with multiple traces of agent executions.
#
# Expected structure: `{ "id": "...", "name": "...", "description": "...", "threads": [...] }`
# where each thread in the array has `id`, `name`, and `traces` fields.
#
# + evalSetPath - Path to the JSON file containing the evaluation dataset
# + return - Map of conversation threads indexed by thread ID, or an `Error` if the file cannot be read or parsed
public isolated function loadConversationThreads(string evalSetPath) returns map<[readonly & ConversationThread]>|Error {
    do {
        json traceJson = check io:fileReadJson(evalSetPath);
        TraceDataset dataset = check traceJson.fromJsonWithType();
        map<[readonly & ConversationThread]> threadsById = {};

        foreach RawConversationThread rawThread in dataset.threads {
            (readonly & Trace)[] conversationTraces = [];
            foreach RawTrace rawTrace in rawThread.traces {
                ChatAssistantMessage|string rawOutput = rawTrace.output;
                readonly & ChatAssistantMessage|Error finalOutput = rawOutput is ChatAssistantMessage
                    ? rawOutput.cloneReadOnly() : error(rawOutput);

                time:Utc traceStartTime = check getUtcTime(rawTrace.startTime);
                time:Utc traceEndTime = check getUtcTime(rawTrace.endTime);

                (readonly & Iteration)[] agentIterations = [];
                foreach var rawIteration in rawTrace.iterations {
                    time:Utc iterationStartTime = check getUtcTime(rawIteration.startTime);
                    time:Utc iterationEndTime = check getUtcTime(rawIteration.endTime);

                    ChatAssistantMessage|ChatFunctionMessage|string rawIterationOutput = rawIteration.output;
                    readonly & (ChatAssistantMessage|ChatFunctionMessage|Error) iterationOutput =
                        rawIterationOutput is string ? error(rawIterationOutput) : rawIterationOutput.cloneReadOnly();

                    readonly & ChatMessage[] messageHistory = rawIteration.history.'map(msg => getChatMessage(msg))
                        .cloneReadOnly();
                    readonly & Iteration agentIteration = {
                        startTime: iterationStartTime,
                        endTime: iterationEndTime,
                        output: iterationOutput,
                        history: messageHistory
                    };
                    agentIterations.push(agentIteration);
                }

                readonly & Trace conversationTrace = {
                    id: rawTrace.id,
                    output: finalOutput,
                    userMessage: getChatUserMessage(rawTrace.userMessage),
                    tools: rawTrace.tools.cloneReadOnly(),
                    startTime: traceStartTime,
                    endTime: traceEndTime,
                    iterations: agentIterations.cloneReadOnly(),
                    toolCalls: rawTrace.toolCalls.cloneReadOnly()
                };
                conversationTraces.push(conversationTrace);
            }

            readonly & ConversationThread thread = {
                id: rawThread.id,
                name: rawThread.name,
                traces: conversationTraces.cloneReadOnly()
            };
            threadsById[thread.id] = [thread];
        }

        return threadsById;
    } on fail error e {
        return error("failed to load conversation threads", e);
    }
}

isolated function getUtcTime(time:Utc|string timestamp) returns time:Utc|error {
    if timestamp is time:Utc {
        return timestamp;
    }
    return time:utcFromString(timestamp);
}

# Represents a conversation thread containing multiple agent interaction traces.
public type ConversationThread record {|
    # Unique identifier for the conversation thread
    string id;
    # Human-readable name or description of the conversation thread
    string name;
    # Sequence of traces representing individual agent executions within this thread
    readonly & Trace[] traces;
|};

type TraceDataset record {
    string id;
    string name;
    string description;
    RawConversationThread[] threads;
};

type RawConversationThread record {
    string id;
    string name;
    RawTrace[] traces;
};

type RawTrace record {|
    string id;
    TraceChatUserMessage userMessage;
    RawIteration[] iterations;
    ChatAssistantMessage|string output;
    ToolSchema[] tools;
    string|time:Utc startTime;
    string|time:Utc endTime;
    FunctionCall[] toolCalls?;
|};

type RawIteration record {|
    TraceChatMessage[] history;
    ChatAssistantMessage|ChatFunctionMessage|string output;
    string|time:Utc startTime;
    string|time:Utc endTime;
|};

type TraceChatSystemMessage record {|
    SYSTEM role;
    string content;
    string name?;
|};

type TraceChatUserMessage record {|
    USER role;
    string content;
    string name?;
|};

type TraceChatMessage TraceChatUserMessage|TraceChatSystemMessage|ChatAssistantMessage|ChatFunctionMessage;

isolated function getChatUserMessage(TraceChatUserMessage message) returns readonly & ChatUserMessage => {
    role: message.role,
    content: message.content,
    name: message.name
};

isolated function getChatMessage(TraceChatMessage message) returns readonly & ChatMessage {
    if message is TraceChatUserMessage {
        return getChatUserMessage(message);
    }
    if message is TraceChatSystemMessage {
        return {
            role: message.role,
            content: message.content,
            name: message.name
        };
    }
    return message.cloneReadOnly();
}
