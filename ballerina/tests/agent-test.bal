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
    SystemPrompt systemPrompt = {role: "Helpful Assistant", instructions: "Answer the questions"};
    string query = "Who is Leo DiCaprio's girlfriend? What is her current age raised to the 0.43 power?";
    ExecutorConfig config = {
        toolStore: check new (searchTool, calculatorTool),
        model: model,
        toolLoadingStrategy: NO_FILTER,
        agentCredential: (),
        tokenManager: new,
        memory: check new ShortTermMemory(),
        stateless: true
    };
    Executor agentExecutor = new (config, DEFAULT_SESSION_ID, 5, false,
        instruction = getFomatedSystemPrompt(systemPrompt), query = query, context = new, executionId = DEFAULT_EXECUTION_ID,
        history = []
    );
    string|FunctionCall|Error llmResponse = agentExecutor.reason();
    if llmResponse is Error|string {
        test:assertFail(string `Expected FunctionCall, but found string|Error.`);
    }
    ExecutionResult|ExecutionError|string output = agentExecutor.act(llmResponse);
    if output is Error|string {
        test:assertFail(string `Expected ExecutionResult|ExecutionError, but found string|Error.`);
    }
    test:assertEquals(output?.observation, "Camila Morrone");

    llmResponse = agentExecutor.reason();
    if llmResponse is Error|string {
        test:assertFail(string `Expected FunctionCall, but found string|Error.`);
    }
    output = agentExecutor.act(llmResponse);
    if output is Error|string {
        test:assertFail(string `Expected ExecutionResult|ExecutionError, but found string|Error.`);
    }
    test:assertEquals(output?.observation, "25 years");

    llmResponse = agentExecutor.reason();
    if llmResponse is Error|string {
        test:assertFail(string `Expected FunctionCall, but found string|Error.`);
    }
    output = agentExecutor.act(llmResponse);
    if output is Error|string {
        test:assertFail(string `Expected ExecutionResult|ExecutionError, but found string|Error.`);
    }
    test:assertEquals(output?.observation, "Answer: 3.991298452658078");
}

@test:Config
function testAgentRunHavingErrorStep() returns error? {
    SystemPrompt systemPrompt = {role: "Helpful Assistant", instructions: "Answer the questions"};
    string query = "Random query";
    ExecutorConfig config = {
        toolStore: check new (searchTool, calculatorTool),
        model: model,
        toolLoadingStrategy: NO_FILTER,
        agentCredential: (),
        tokenManager: new,
        memory: check new ShortTermMemory(),
        stateless: true
    };
    ExecutionTrace trace = run(config, instruction = getFomatedSystemPrompt(systemPrompt), query = query,
            context = new, maxIter = 5, verbose = false);
    test:assertEquals(trace.answer is (), true);
    test:assertEquals(trace.steps.length(), 1);
    test:assertEquals(trace.steps[0] is Error, true);
}
