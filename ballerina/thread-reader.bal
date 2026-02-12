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
public isolated function loadConversationThreads(string evalSetPath) returns map<[ConversationThread]>|Error {
    do {
        json traceJson = check io:fileReadJson(evalSetPath);
        TraceDataset dataset = check traceJson.fromJsonWithType();
        map<[ConversationThread]> threadsById = {};

        foreach RawConversationThread rawThread in dataset.threads {
            Trace[] conversationTraces = [];
            foreach RawTrace rawTrace in rawThread.traces {
                ChatAssistantMessage|string rawOutput = rawTrace.output;
                ChatAssistantMessage|Error finalOutput = rawOutput is ChatAssistantMessage
                    ? rawOutput : error(rawOutput);

                time:Utc traceStartTime = check getUtcTime(rawTrace.startTime);
                time:Utc traceEndTime = check getUtcTime(rawTrace.endTime);

                Iteration[] agentIterations = [];
                foreach var rawIteration in rawTrace.iterations {
                    time:Utc iterationStartTime = check getUtcTime(rawIteration.startTime);
                    time:Utc iterationEndTime = check getUtcTime(rawIteration.endTime);

                    ChatAssistantMessage|ChatFunctionMessage|string rawIterationOutput = rawIteration.output;
                    ChatAssistantMessage|ChatFunctionMessage|Error iterationOutput = rawIterationOutput is string
                        ? error(rawIterationOutput) : rawIterationOutput;

                    ChatMessage[] messageHistory = rawIteration.history.'map(msg => getChatMessage(msg));
                    Iteration agentIteration = {
                        startTime: iterationStartTime,
                        endTime: iterationEndTime,
                        output: iterationOutput,
                        history: messageHistory
                    };
                    agentIterations.push(agentIteration);
                }

                Trace conversationTrace = {
                    id: rawTrace.id,
                    output: finalOutput,
                    userMessage: getChatUserMessage(rawTrace.userMessage),
                    tools: rawTrace.tools,
                    startTime: traceStartTime,
                    endTime: traceEndTime,
                    iterations: agentIterations,
                    toolCalls: rawTrace.toolCalls
                };
                conversationTraces.push(conversationTrace);
            }

            ConversationThread thread = {id: rawThread.id, name: rawThread.name, traces: conversationTraces};
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
    Trace[] traces;
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

isolated function getChatUserMessage(TraceChatUserMessage message) returns ChatUserMessage => {
    role: message.role,
    content: message.content,
    name: message.name
};

isolated function getChatMessage(TraceChatMessage message) returns ChatMessage {
    if message is TraceChatUserMessage {
        return getChatUserMessage(message);
    }
    if message is TraceChatSystemMessage {
        ChatSystemMessage systemMessage = {
            role: message.role,
            content: message.content,
            name: message.name
        };
        return systemMessage;
    }
    return message;
}
