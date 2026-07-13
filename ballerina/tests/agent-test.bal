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

ToolConfig slowSearchTool = {
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
    caller: slowSearchToolMock
};

ToolConfig slowCalculatorTool = {
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
    caller: slowCalculatorToolMock
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
    Executor agentExecutor = new (agent, DEFAULT_SESSION_ID, maxIter = 5,
        instruction = "Answer the questions", query = query, context = new, executionId = DEFAULT_EXECUTION_ID,
        history = []
    );
    test:assertEquals(runNextIteration(agentExecutor), "Camila Morrone");
    test:assertEquals(runNextIteration(agentExecutor), "25 years");
    test:assertEquals(runNextIteration(agentExecutor), "Answer: 3.991298452658078");
}

// Runs the next reasoning-action cycle of the executor and returns the observation
// of its single tool call.
function runNextIteration(Executor agentExecutor) returns anydata {
    record {|(ExecutionResult|ExecutionError)[]|string|Error value;|}? result = agentExecutor.next();
    if result is () {
        test:assertFail("AgentExecutor.next returned null before the execution completed");
    }
    (ExecutionResult|ExecutionError)[]|string|Error output = result.value;
    if output !is (ExecutionResult|ExecutionError)[] {
        test:assertFail(string `Expected tool execution results, but got ${output is Error ? output.message() : output}`);
    }
    test:assertEquals(output.length(), 1);
    ExecutionResult|ExecutionError step = output[0];
    if step !is ExecutionResult {
        test:assertFail(string `Expected a successful tool execution, but got ${step.toString()}`);
    }
    anydata|error observation = step.observation;
    return observation is error ? observation.toString() : observation;
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

    // One iteration per reasoning-action cycle: the first holds both tool observations from
    // the single LLM response, and the second holds the final answer.
    test:assertEquals(trace.iterations.length(), 2);
    (ChatAssistantMessage|ChatFunctionMessage|Error)[] toolCallIterationOutput = trace.iterations[0].output;
    test:assertEquals(toolCallIterationOutput.length(), 2);
    ChatAssistantMessage|ChatFunctionMessage|Error searchOutput = toolCallIterationOutput[0];
    test:assertTrue(searchOutput is ChatFunctionMessage);
    if searchOutput is ChatFunctionMessage {
        test:assertEquals(searchOutput.name, "Search");
        test:assertEquals(searchOutput.content, "Camila Morrone");
    }
    ChatAssistantMessage|ChatFunctionMessage|Error calculatorOutput = toolCallIterationOutput[1];
    test:assertTrue(calculatorOutput is ChatFunctionMessage);
    if calculatorOutput is ChatFunctionMessage {
        test:assertEquals(calculatorOutput.name, "Calculator");
        test:assertEquals(calculatorOutput.content, "Answer: 3.991298452658078");
    }
    (ChatAssistantMessage|ChatFunctionMessage|Error)[] finalIterationOutput = trace.iterations[1].output;
    test:assertEquals(finalIterationOutput.length(), 1);
    test:assertTrue(finalIterationOutput[0] is ChatAssistantMessage);

    // Only 2 LLM calls were made: one that returned both tool calls together, and one that
    // produced the final answer after both tool results were available. Previously, executing
    // 2 tool calls required 3 LLM calls, one per tool call plus the final answer, because only
    // the first tool call in a response was ever acted on.
    test:assertEquals(scriptedModel.getChatCallCount(), 2);
}

@test:Config
function testMaxIterCountsReasoningActionCyclesNotToolCalls() returns error? {
    MultiToolCallMockLLM scriptedModel = new;
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Answer the questions"},
        model: scriptedModel,
        tools: [searchTool, calculatorTool],
        maxIter: 2
    });

    // Cycle 1: the LLM returns both tool calls in a single response. Cycle 2: the final answer.
    // With `maxIter: 2` this must succeed because the two tool calls belong to a single
    // reasoning-action cycle. Counting each tool call as its own iteration would exhaust
    // the limit before the final answer and fail with `MaxIterationExceededError`.
    string answer = check agent.run("Who is Leo DiCaprio's girlfriend, and what is 25 raised to the power of 0.43?");

    test:assertEquals(answer, "Leo DiCaprio's girlfriend is Camila Morrone, and 25 raised to the " +
            "power of 0.43 is Answer: 3.991298452658078");
    test:assertEquals(scriptedModel.getChatCallCount(), 2);
}

@test:Config
function testMaxIterationExceededErrorWhenAgentNeverProducesFinalAnswer() returns error? {
    NeverAnsweringMockLLM scriptedModel = new;
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Answer the questions"},
        model: scriptedModel,
        tools: [searchTool, calculatorTool],
        maxIter: 3
    });

    string|Error result = agent.run("Who is Leo DiCaprio's girlfriend?");

    test:assertTrue(result is MaxIterationExceededError,
            string `Expected MaxIterationExceededError, but got ${(typeof result).toString()}`);
    // The limit is enforced before each reasoning call, so exactly `maxIter` LLM calls are
    // made and no extra call is wasted once the budget is spent.
    test:assertEquals(scriptedModel.getChatCallCount(), 3);
}

@test:Config
function testAgentRunExecutesToolCallsInParallel() returns error? {
    MultiToolCallMockLLM scriptedModel = new;
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Answer the questions"},
        model: scriptedModel,
        tools: [slowSearchTool, slowCalculatorTool],
        executeToolCallsInParallel: true
    });

    // The mock LLM returns both tool calls together, and each slow tool sleeps for 1 second
    // while recording its execution time window.
    Trace trace = check agent.run("Who is Leo DiCaprio's girlfriend, and what is 25 raised to the power of 0.43?");

    // The answer and executed tool calls are identical to sequential execution.
    ChatAssistantMessage|Error output = trace.output;
    test:assertTrue(output is ChatAssistantMessage);
    if output is ChatAssistantMessage {
        test:assertEquals(output.content, "Leo DiCaprio's girlfriend is Camila Morrone, and 25 raised to the " +
                "power of 0.43 is Answer: 3.991298452658078");
    }
    FunctionCall[]? toolCalls = trace.toolCalls;
    test:assertTrue(toolCalls is FunctionCall[]);
    if toolCalls is FunctionCall[] {
        test:assertEquals(toolCalls.length(), 2);
        test:assertEquals(toolCalls[0].name, "Search");
        test:assertEquals(toolCalls[1].name, "Calculator");
    }
    test:assertEquals(trace.iterations.length(), 2);
    test:assertEquals(scriptedModel.getChatCallCount(), 2);

    // Both tool executions overlapped in time, proving they ran in parallel rather than
    // one after the other.
    [decimal, decimal] searchWindow = check getToolExecutionWindow("Search");
    [decimal, decimal] calculatorWindow = check getToolExecutionWindow("Calculator");
    test:assertTrue(searchWindow[0] < calculatorWindow[1] && calculatorWindow[0] < searchWindow[1],
            string `Expected tool executions to overlap, but Search ran during ${searchWindow.toString()} ` +
            string `and Calculator ran during ${calculatorWindow.toString()}`);
}

@test:Config
function testAgentRunExecutesToolCallsSequentially() returns error? {
    MultiToolCallMockLLM scriptedModel = new;
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Answer the questions"},
        model: scriptedModel,
        tools: [slowSearchTool, slowCalculatorTool],
        executeToolCallsInParallel: false
    });

    string answer = check agent.run("Who is Leo DiCaprio's girlfriend, and what is 25 raised to the power of 0.43?");

    test:assertEquals(answer, "Leo DiCaprio's girlfriend is Camila Morrone, and 25 raised to the " +
            "power of 0.43 is Answer: 3.991298452658078");
    test:assertEquals(scriptedModel.getChatCallCount(), 2);

    // With `executeToolCallsInParallel` disabled, the Search tool completes before
    // the Calculator tool starts.
    [decimal, decimal] searchWindow = check getToolExecutionWindow("Search");
    [decimal, decimal] calculatorWindow = check getToolExecutionWindow("Calculator");
    test:assertTrue(searchWindow[1] <= calculatorWindow[0],
            string `Expected tool executions to run sequentially, but Search ran during ` +
            string `${searchWindow.toString()} and Calculator ran during ${calculatorWindow.toString()}`);
}
