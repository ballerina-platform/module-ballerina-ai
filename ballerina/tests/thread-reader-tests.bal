// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
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

import ballerina/test;

@test:Config
isolated function testLoadConversationThreads() returns error? {
    string datasetPath = "tests/resources/evaluation-dataset/sessions.evalset.json";
    map<[ConversationThread]> threads = check loadConversationThreads(datasetPath);
    test:assertEquals(threads.keys().length(), 2);

    string threadId = "thread-01";
    [ConversationThread] [thread] = threads.get(threadId);
    test:assertEquals(thread.id, threadId);

    Trace[] traces = thread.traces;
    test:assertEquals(traces.length(), 4);

    Trace trace_2 = traces[2];
    test:assertEquals(getChatMessageStringContent(trace_2.userMessage.content), "2-8+9?");

    test:assertEquals(trace_2.iterations.length(), 3);
    test:assertEquals(trace_2.iterations[2].history.length(), 12);
    test:assertEquals(trace_2.tools.length(), 4);

    FunctionCall[] expectedToolCalls = [
        {name: "subtractTool", arguments: {num1: 2, num2: 8}},
        {name: "sumTool", arguments: {num1: -6, num2: 9}}
    ];
    test:assertEquals(trace_2.toolCalls, expectedToolCalls);
}

isolated function buildMinimalTrace(string|Prompt content) returns Trace => {
    id: "test-trace",
    userMessage: {role: USER, content},
    iterations: [],
    output: {role: ASSISTANT, content: "answer"},
    tools: [],
    startTime: [0, 0.0d],
    endTime: [0, 0.0d]
};

@test:Config
isolated function testGetUserQueryWithStringContent() {
    Trace trace = buildMinimalTrace("What is 2+2?");
    test:assertEquals(getUserQuery(trace), "What is 2+2?");
}

@test:Config
isolated function testGetUserQueryWithPromptContent() {
    int a = 2;
    int b = 2;
    Trace trace = buildMinimalTrace(`What is ${a}+${b}?`);
    test:assertEquals(getUserQuery(trace), "What is 2+2?");
}
