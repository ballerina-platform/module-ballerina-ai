import ballerina/test;
import ballerina/os;
import ballerina/http;
import ballerina/jballerina.java;
import ballerina/lang.runtime;
import ai.observability;

@test:Config {
    enable: true,
    before: startPhoenix,
    after: stopPhoenix
}
function testSimpleAgentFlow() {
    if isWindows() {
        return;
    }
    observability:initTracing("http://localhost:6006/v1/traces", "test-from-ballerina");
    observability:AgentSpan agentSpan = observability:createAgentSpan("agent");
    agentSpan.enter();
    agentSpan.setInput("hi");
    {
        observability:LLMSpan llmSpan = observability:createLLMSpan("llm", "gpt-4o-mini", "openai");
        llmSpan.enter();
        llmSpan.setInput("hi llm");
        map<json> toolInput = {
            "arg1": "value1",
            "arg2": "value2"
        };
        observability:ToolCallRequest toolCallRequest = {
            name: "tool",
            id: "123",
            argumentJson: toolInput
        };
        llmSpan.addToolCallRequests(toolCallRequest);
        {
            observability:ToolSpan toolSpan = observability:createToolSpan("tool");
            toolSpan.enter();
            toolSpan.setInput("hi tool");
            toolSpan.setOutput("bye tool");
            toolSpan.setStatus(observability:OK);
            toolSpan.exit();
        }
        observability:ToolCallResponse toolCallResponse = {
            name: "tool",
            id: "123",
            content: "bye tool"
        };
        llmSpan.addToolCallResponse(toolCallResponse);
        llmSpan.addIntermediateRequest("what is the output of the tool?");
        llmSpan.addIntermediateResponse("the output of the tool is great");
        llmSpan.setOutput("final llm output");
        llmSpan.setTokenCount(100, 50, 50);
        llmSpan.setStatus(observability:OK);
        llmSpan.exit();
    }
    agentSpan.setOutput("bye agent");
    agentSpan.setStatus(observability:OK);
    agentSpan.exit();
}

enum OS {
    LINUX,
    DARWIN,
    WINDOWS,
    UNKNOWN
}

function getOS() returns OS {
    string? os = getProperty("os.name");
    if os == () {
        return UNKNOWN;
    }
    string osString = os.toLowerAscii();
    if osString.includes("mac") || osString.includes("darwin") {
        return DARWIN;
    } else if osString.includes("linux") {
        return LINUX;
    } else if osString.includes("windows") {
        return WINDOWS;
    } else {
        return UNKNOWN;
    }
}

function isWindows() returns boolean {
    return getOS() == WINDOWS;
}

function setupPhoenix() {
    // Pull the Phoenix container image
    _ = checkpanic os:exec({ value: "docker", arguments: ["pull", "arizephoenix/phoenix:latest"] });
}

function startPhoenix() {
    if isWindows() {
        return;
    }
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
    var result = checkpanic os:exec({
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
    if result.waitForExit() != 0 {
        panic error("Failed to start Phoenix container");
    }
    // Wait for Phoenix to be ready
    waitForPhoenix();
}

function checkHealth() returns boolean|error {
    http:Client httpClient = check new ("http://localhost:6006");
    http:Response response = check httpClient->get("/healthz");
    return response.statusCode == 200;
}

function waitForPhoenix() {
    int maxWaitTime = 3 * 60; // seconds
    int waitTime = 0;

    while waitTime < maxWaitTime {
        boolean|error healthCheck = checkHealth();
        if healthCheck is boolean && healthCheck {
            return;
        }

        runtime:sleep(5);
        waitTime += 5;
    }

    panic error("Phoenix failed to start within " + maxWaitTime.toString() + " seconds");
}

function stopPhoenix() {
    if isWindows() {
        return;
    }
    _ = checkpanic os:exec({ value: "docker", arguments: ["stop", "phoenix-otel-collector"] });
    _ = checkpanic os:exec({ value: "docker", arguments: ["rm", "phoenix-otel-collector"] });
}

function getProperty(string property) returns string? {
    return java:toString(getPropertyNative(java:fromString(property)));
}

isolated function getPropertyNative(handle property) returns handle = @java:Method {
    'class: "java.lang.System",
    name: "getProperty"
} external;
