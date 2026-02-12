// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
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

import ballerina/ai;
import ballerina/test;

@test:Config
isolated function testTraceBinding() returns error? {
    string query = "What is the sum of the following numbers 78 90 45 23 8?";
    ai:Trace trace = check agent.run(query);

    test:assertEquals(trace.userMessage.content, query);

    ai:ChatAssistantMessage|ai:Error output = trace.output;
    if output is ai:Error {
        return output;
    }

    int expectedToolCount = 6;
    test:assertEquals(trace.tools.length(), expectedToolCount);

    int expectedIterationCount = 2;
    test:assertEquals(trace.iterations.length(), expectedIterationCount);

    int expectedSecondIterationHistoryCount = 14;
    test:assertEquals(
            trace.iterations[1].history.length(),
            expectedSecondIterationHistoryCount
    );

    test:assertEquals(output.content, "Answer is: 244");
}

@test:Config
isolated function testTraceHavingToolCallsOfTurn() returns error? {
    string query = "What is the sum of the following numbers 78 90 45 23 8?";
    ai:Trace trace = check agent.run(query);
    ai:ChatAssistantMessage output = check trace.output;
    test:assertEquals(output.content, "Answer is: 244");
    ai:FunctionCall[]? toolCalls = trace.toolCalls;
    if toolCalls is () {
        test:assertFail("Expected a tool array found null");
    }
    test:assertEquals(toolCalls.length(), 1);
    test:assertEquals(toolCalls[0].name, "sum");
}
