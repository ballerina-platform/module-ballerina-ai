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
    FunctionCallAgent agent = check new (model, [searchTool, calculatorTool]);
    string query = "Who is Leo DiCaprio's girlfriend? What is her current age raised to the 0.43 power?";
    Executor agentExecutor = new (agent, DEFAULT_SESSION_ID,
        instruction = "Answer the questions", query = query, context = new
    );
    record {|ExecutionResult|LlmChatResponse|ExecutionError|Error value;|}? result = agentExecutor.next();
    if result is () {
        test:assertFail("AgentExecutor.next returns an null during first iteration");
    }
    ExecutionResult|LlmChatResponse|ExecutionError|Error output = result.value;
    if output is Error {
        test:assertFail("AgentExecutor.next returns an error during first iteration");
    }
    test:assertEquals(output?.observation, "Camila Morrone");

    result = agentExecutor.next();
    if result is () {
        test:assertFail("AgentExecutor.next returns an null during second iteration");
    }
    output = result.value;
    if output is Error {
        test:assertFail("AgentExecutor.next returns an error during second iteration");
    }
    test:assertEquals(output?.observation, "25 years");

    result = agentExecutor.next();
    if result is () {
        test:assertFail("AgentExecutor.next returns an null during third iteration");
    }
    output = result.value;
    if output is Error {
        test:assertFail("AgentExecutor.next returns an error during third iteration");
    }
    test:assertEquals(output?.observation, "Answer: 3.991298452658078");
}
