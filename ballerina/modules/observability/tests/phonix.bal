import ballerina/test;
import ballerina/os;
import ballerina/http;
@test:Config {
    enable: true,
    before: startPhoenix,
    after: stopPhoenix
}
function testSimpleAgentFlow() {
    initTracing("http://localhost:6006/v1/traces", "test-from-ballerina");
    AgentSpan agentSpan = createAgentSpan("agent");
    agentSpan.enter();
    agentSpan.setInput("hi");
    {
        LLMSpan llmSpan = createLLMSpan("llm", "gpt-4o-mini", "openai");
        llmSpan.enter();
        llmSpan.setInput("hi llm");
        map<json> toolInput = {
            "arg1": "value1",
            "arg2": "value2"
        };
        ToolCallRequest toolCallRequest = {
            name: "tool",
            id: "123",
            argumentJson: toolInput
        };
        llmSpan.addToolCallRequests(toolCallRequest);
        {
            ToolSpan toolSpan = createToolSpan("tool");
            toolSpan.enter();
            toolSpan.setInput("hi tool");
            toolSpan.setOutput("bye tool");
            toolSpan.setStatus(OK);
            toolSpan.exit();
        }
        ToolCallResponse toolCallResponse = {
            name: "tool",
            id: "123",
            content: "bye tool"
        };
        llmSpan.addToolCallResponse(toolCallResponse);
        llmSpan.addIntermediateRequest("what is the output of the tool?");
        llmSpan.addIntermediateResponse("the output of the tool is great");
        llmSpan.setOutput("final llm output");
        llmSpan.setTokenCount(100, 50, 50);
        llmSpan.setStatus(OK);
        llmSpan.exit();
    }
    agentSpan.setOutput("bye agent");
    agentSpan.setStatus(OK);
    agentSpan.exit();
}

function setupPhoenix() {
    // Pull the Phoenix container image
    _ = checkpanic os:exec({ value: "docker", arguments: ["pull", "arizephoenix/phoenix:latest"] });
}

function startPhoenix() {
    // Setup Phoenix first
    setupPhoenix();

    // Check if Phoenix is already running
    boolean|error healthCheck = checkHealth();
    if healthCheck is boolean && healthCheck {
        return;
    }

    // Stop any existing Phoenix container
    _ = checkpanic os:exec({ value: "docker", arguments: ["stop", "phoenix-otel-collector"] });
    _ = checkpanic os:exec({ value: "docker", arguments: ["rm", "phoenix-otel-collector"] });

    // Start new Phoenix container with proper configuration
    _ = checkpanic os:exec({
        value: "docker",
        arguments: [
            "run", "-d",
            "--name", "phoenix-otel-collector",
            "-p", "6006:6006",
            "-p", "4317:4317",
            "-p", "9091:9090",
            "arizephoenix/phoenix:latest"
        ]
    });

    // Wait for Phoenix to be ready
    waitForPhoenix();
}

function checkHealth() returns boolean|error {
    http:Client httpClient = check new ("http://localhost:6006");
    http:Response response = check httpClient->get("/healthz");
    return response.statusCode == 200;
}

function waitForPhoenix() {
    int maxWaitTime = 120; // seconds
    int waitTime = 0;

    while waitTime < maxWaitTime {
        boolean|error healthCheck = checkHealth();
        if healthCheck is boolean && healthCheck {
            return;
        }

        // Wait 5 seconds before next check
        // Using a simple loop for delay since runtime:sleep is not available
        int i = 0;
        while i < 5000000 {
            i += 1;
        }
        waitTime += 5;
    }

    panic error("Phoenix failed to start within " + maxWaitTime.toString() + " seconds");
}

function stopPhoenix() {
    _ = checkpanic os:exec({ value: "docker", arguments: ["stop", "phoenix-otel-collector"] });
    _ = checkpanic os:exec({ value: "docker", arguments: ["rm", "phoenix-otel-collector"] });
}
