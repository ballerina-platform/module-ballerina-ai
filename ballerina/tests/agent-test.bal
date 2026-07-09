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

import ballerina/test;

ToolConfig searchTool = {
    name: "Search",
    description: " A search engine. Useful for when you need to answer questions about current events",
    parameters: {
        properties: {
            params: {
                properties: {
                    query: {'type: "string", description: "The search query"}
                }
            }
        }
    },
    caller: searchToolMock
};

ToolConfig calculatorTool = {
    name: "Calculator",
    description: "Useful for when you need to answer questions about math.",
    parameters: {
        properties: {
            params: {
                properties: {
                    expression: {'type: "string", description: "The mathematical expression to evaluate"}
                }
            }
        }
    },
    caller: calculatorToolMock
};

ModelProvider model = new MockLLM();

@test:Config {
    enable: false
}
function testAgentExecutorRun() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Answer the questions"},
        model,
        tools: [searchTool, calculatorTool]
    });
    string query = "Who is Leo DiCaprio's girlfriend? What is her current age raised to the 0.43 power?";
    Executor agentExecutor = new (agent, DEFAULT_SESSION_ID,
        instruction = "Answer the questions", query = query, context = new, executionId = DEFAULT_EXECUTION_ID,
        history = []
    );
    record {|ExecutionResult|string|ExecutionError|Error value;|}? result = agentExecutor.next();
    if result is () {
        test:assertFail("AgentExecutor.next returns an null during first iteration");
    }
    ExecutionResult|string|ExecutionError|Error output = result.value;
    if output is Error {
        test:assertFail("AgentExecutor.next returns an error during first iteration");
    }
    test:assertEquals(output, "Camila Morrone");

    result = agentExecutor.next();
    if result is () {
        test:assertFail("AgentExecutor.next returns an null during second iteration");
    }
    output = result.value;
    if output is Error {
        test:assertFail("AgentExecutor.next returns an error during second iteration");
    }
    test:assertEquals(output, "25 years");

    result = agentExecutor.next();
    if result is () {
        test:assertFail("AgentExecutor.next returns an null during third iteration");
    }
    output = result.value;
    if output is Error {
        test:assertFail("AgentExecutor.next returns an error during third iteration");
    }
    test:assertEquals(output, "Answer: 3.991298452658078");
}

@test:Config
function testAgentRunHavingErrorStep() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Answer the questions"},
        model,
        tools: [searchTool, calculatorTool]
    });
    string query = "Random query";
    ExecutionTrace trace = run(agent, instruction = "Answer the questions", query = query,
            context = new, maxIter = 5, verbose = false, agentId = ());
    test:assertEquals(trace.answer is (), true);
    test:assertEquals(trace.steps.length(), 1);
    test:assertEquals(trace.steps[0] is Error, true);
}

@test:Config
function testAgentRecoversFromBadlyFormattedHistoryWithoutCorruptingMemory() returns error? {
    ModelProvider scriptedModel = new ScriptedMockLLM();
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Answer the questions"},
        model: scriptedModel,
        tools: [searchTool, calculatorTool]
    });

    // Turn 1: a normal, successful exchange.
    string firstResult = check agent.run("first turn query");
    test:assertEquals(firstResult, "first turn answer");

    // Turn 2: the mock returns a response with neither `content` nor `toolCalls`, which the
    // agent can't parse into a tool call or a final answer. It records the raw response as an
    // execution step, and replaying that step from history on the next reasoning iteration used
    // to `panic` and crash the whole run. It should now surface as a recoverable `Error` instead.
    string|Error secondResult = agent.run("second turn query");
    test:assertTrue(secondResult is Error);
    if secondResult is Error {
        string detail = secondResult.detail().toString();
        test:assertTrue(detail.includes("Failed to parse the LLM response into a function call or chat message."));
    }

    // Turn 3: a normal exchange again, using the same session. If the failed turn had persisted
    // the badly-formatted step into conversation memory, this turn would panic/fail too.
    string thirdResult = check agent.run("third turn query");
    test:assertEquals(thirdResult, "third turn answer");
}

@test:Config
function testAgentRunExecutesMultipleToolCallsFromSingleLlmResponseTogether() returns error? {
    MultiToolCallMockLLM scriptedModel = new;
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Answer the questions"},
        model: scriptedModel,
        tools: [searchTool, calculatorTool]
    });

    // The mock LLM returns both the `Search` and `Calculator` tool calls together in a single
    // response. The agent must execute both before consulting the LLM again, and the LLM then
    // answers both questions at once in a single final response.
    Trace trace = check agent.run("Who is Leo DiCaprio's girlfriend, and what is 25 raised to the power of 0.43?",
            td = Trace);

    // Final answer covers both questions, generated from a single follow-up LLM call.
    ChatAssistantMessage|Error output = trace.output;
    test:assertTrue(output is ChatAssistantMessage);
    if output is ChatAssistantMessage {
        test:assertEquals(output.content, "Leo DiCaprio's girlfriend is Camila Morrone, and 25 raised to the " +
                "power of 0.43 is Answer: 3.991298452658078");
    }

    // Both tool calls from the single LLM response were captured and executed.
    FunctionCall[]? toolCalls = trace.toolCalls;
    test:assertTrue(toolCalls is FunctionCall[]);
    if toolCalls is FunctionCall[] {
        test:assertEquals(toolCalls.length(), 2);
        test:assertEquals(toolCalls[0].name, "Search");
        test:assertEquals(toolCalls[1].name, "Calculator");
    }

    // Intermediate tool observations are present, one iteration per tool call, followed by the
    // final answer iteration.
    test:assertEquals(trace.iterations.length(), 3);
    ChatAssistantMessage|ChatFunctionMessage|Error searchIterationOutput = trace.iterations[0].output;
    test:assertTrue(searchIterationOutput is ChatFunctionMessage);
    if searchIterationOutput is ChatFunctionMessage {
        test:assertEquals(searchIterationOutput.name, "Search");
        test:assertEquals(searchIterationOutput.content, "Camila Morrone");
    }
    ChatAssistantMessage|ChatFunctionMessage|Error calculatorIterationOutput = trace.iterations[1].output;
    test:assertTrue(calculatorIterationOutput is ChatFunctionMessage);
    if calculatorIterationOutput is ChatFunctionMessage {
        test:assertEquals(calculatorIterationOutput.name, "Calculator");
        test:assertEquals(calculatorIterationOutput.content, "Answer: 3.991298452658078");
    }
    ChatAssistantMessage|ChatFunctionMessage|Error finalIterationOutput = trace.iterations[2].output;
    test:assertTrue(finalIterationOutput is ChatAssistantMessage);

    // Only 2 LLM calls were made: one that returned both tool calls together, and one that
    // produced the final answer after both tool results were available. Previously, executing
    // 2 tool calls required 3 LLM calls, one per tool call plus the final answer, because only
    // the first tool call in a response was ever acted on.
    test:assertEquals(scriptedModel.getChatCallCount(), 2);
}
