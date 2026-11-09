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

import ballerina/http;
import ballerina/mcp;
import ballerina/mcp.v2 as mcpv2;
import ballerina/test;

const MODERN_MCP_SERVER_URL = "http://localhost:9098/mcp";

listener mcpv2:StreamableHttpListener modernMcpListener = check new (9098);

@mcpv2:StreamableHttpServiceConfig {info: {name: "Greeting", version: "1.0.0"}}
service mcpv2:StreamableHttpService /mcp on modernMcpListener {
    @mcpv2:Tool {description: "Greets a single person"}
    remote isolated function greet(string greetName) returns string => string `Hey ${greetName}! Welcome to Ballerina!`;
}

isolated class McpV2ToolKit {
    *McpBaseToolKit;
    private final mcpv2:StreamableHttpClient mcpClient;
    private final readonly & ToolConfig[] tools;

    public isolated function init(string serverUrl) returns Error? {
        do {
            self.mcpClient = check new mcpv2:StreamableHttpClient(serverUrl);
            self.tools = check getPermittedMcpToolConfigs(self.mcpClient, {name: "MCP", version: "1.0.0"},
                    self.callTool).cloneReadOnly();
        } on fail error e {
            return error Error("Failed to initialize MCP toolkit", e);
        }
    }

    public isolated function getTools() returns ToolConfig[] => self.tools;

    @AgentTool {name: "callTool", description: "Calls any tool on the MCP server"}
    public isolated function callTool(mcpv2:CallToolParams params) returns mcpv2:CallToolResult|error {
        return self.mcpClient->callTool(params);
    }
}

@test:Config {
    groups: ["mcp"]
}
function testCustomMcpV2ToolKitWithLegacyServer() returns error? {
    McpV2ToolKit mcpToolKit = check new ("http://localhost:3000/mcp");
    ToolConfig[] tools = mcpToolKit.getTools();
    test:assertEquals(tools.length(), 2);
    test:assertEquals(tools[0].name, "single-greeting");

    ToolStore toolStore = check new (mcpToolKit);
    ToolOutput output = check toolStore.execute({name: "single-greeting", arguments: {"greetName": "John"}});
    test:assertEquals((check output.value).toJson(), {
        "content": [{"type": "text", "text": "Hey John! Welcome to Ballerina!"}]
    });
}

@test:Config
function testCustomMcpV2ToolKitWithModernServer() returns error? {
    McpV2ToolKit mcpToolKit = check new (MODERN_MCP_SERVER_URL);
    ToolConfig[] tools = mcpToolKit.getTools();
    test:assertEquals(tools.length(), 1);
    test:assertEquals(tools[0].name, "greet");

    ToolStore toolStore = check new (mcpToolKit);
    ToolOutput output = check toolStore.execute({name: "greet", arguments: {"greetName": "John"}});
    mcpv2:CallToolResult result = check (check output.value).ensureType();
    test:assertEquals(result.content.toJson(), [{"type": "text", "text": "Hey John! Welcome to Ballerina!"}]);
    // The modern result also carries `structuredContent`, `resultType` and `_meta`, none of which reach the model.
    test:assertEquals(unwrapMcpToolResult(result), "Hey John! Welcome to Ballerina!");
}

@test:Config
function testUnwrapMcpToolResultJoinsTextContent() {
    mcp:CallToolResult result = {content: [{'type: "text", text: "Line 1"}, {'type: "text", text: "Line 2"}]};
    test:assertEquals(unwrapMcpToolResult(result), "Line 1\nLine 2");
}

@test:Config
function testUnwrapMcpToolResultKeepsNonTextContent() {
    mcpv2:CallToolResult result = {
        content: [{'type: "text", text: "A chart"}, {'type: "image", data: "aGk=", mimeType: "image/png"}],
        structuredContent: {chart: "bar"}
    };
    test:assertEquals(unwrapMcpToolResult(result), result.content);
}

@test:Config
function testUnwrapMcpToolResultFallsBackToStructuredContent() {
    mcpv2:CallToolResult result = {content: [], structuredContent: {temperature: 22}};
    test:assertEquals(unwrapMcpToolResult(result), {temperature: 22});
}

@test:Config
function testUnwrapMcpToolResultKeepsErrorFlag() {
    mcpv2:CallToolResult result = {content: [{'type: "text", text: "City not found"}], isError: true};
    test:assertEquals(unwrapMcpToolResult(result), {isError: true, content: "City not found"});
}

@test:Config
function testTraceOutputMatchesModelObservationForMcpResult() returns error? {
    mcpv2:CallToolResult result = {
        content: [{'type: "text", text: "Sunny"}],
        structuredContent: {weather: "Sunny"},
        resultType: "complete"
    };
    ChatFunctionMessage output = check getOutputOfStep({tool: {name: "getWeather"}, observation: result});
    test:assertEquals(output.content, "Sunny");
}

@test:Config
function testObservationForEmptyMcpToolResult() {
    mcpv2:CallToolResult result = {content: []};
    test:assertEquals(getObservationString(result),
        "Tool didn't return anything. Probably it is successful. Should we verify using another tool?");
}

@test:Config
function testUnwrapMcpToolResultLeavesOtherValues() {
    record {anydata[] content;} value = {content: []};
    test:assertEquals(unwrapMcpToolResult(value), value);
}

@AgentTool
isolated function mcpV2Dispatcher(mcpv2:CallToolParams params) returns mcpv2:CallToolResult|error => {content: []};

@test:Config
function testPermittedMcpToolConfigsWithEitherImplementation() returns error? {
    mcpv2:Implementation v2Info = {name: "MCP", version: "1.0.0"};
    mcp:Implementation info = {name: "MCP", version: "1.0.0"};
    foreach record {string name; string version;} clientInfo in [v2Info, info] {
        mcpv2:StreamableHttpClient mcpClient = check new (MODERN_MCP_SERVER_URL);
        ToolConfig[] tools = check getPermittedMcpToolConfigs(mcpClient, clientInfo, mcpV2Dispatcher);
        test:assertEquals(tools.map(tool => tool.name), ["greet"]);
    }
}

@test:Config {
    groups: ["mcp"]
}
function testPermittedMcpToolConfigsWithV2ImplementationAndDeprecatedClient() returns error? {
    mcp:StreamableHttpClient mcpClient = check new ("http://localhost:3000/mcp");
    mcpv2:Implementation info = {name: "MCP", version: "1.0.0"};
    ToolConfig[] tools = check getPermittedMcpToolConfigs(mcpClient, info, mcpV2Dispatcher);
    test:assertEquals(tools.length(), 2);
}

// A real mcp.v2 service cannot report whether initialize arrived, so this legacy-only mock records it.
isolated map<string[]> recordedMcpMethods = {};

isolated function recordedMethods(string scenario) returns string[] {
    lock {
        return (recordedMcpMethods[scenario] ?: []).clone();
    }
}

service /recording on new http:Listener(9099) {
    resource function post [string scenario](@http:Payload map<json> payload) returns http:Response|error {
        string method = check payload.method.ensureType();
        lock {
            string[] methods = recordedMcpMethods[scenario] ?: [];
            methods.push(method);
            recordedMcpMethods[scenario] = methods;
        }
        http:Response response = new;
        json id = payload["id"];
        if id is () {
            response.statusCode = http:STATUS_ACCEPTED;
            return response;
        }
        json result = {};
        match method {
            "server/discover" => {
                result = {
                    resultType: "complete",
                    ttlMs: 0,
                    cacheScope: "private",
                    supportedVersions: ["2025-11-25"],
                    capabilities: {}
                };
            }
            "initialize" => {
                result = {protocolVersion: "2025-11-25", capabilities: {}, serverInfo: {name: "mock", version: "1"}};
            }
            "tools/list" => {
                result = {tools: [{name: "echo", inputSchema: {'type: "object"}}]};
            }
        }
        response.setJsonPayload({jsonrpc: "2.0", id, result});
        return response;
    }
}

@test:Config
function testAgentIdentitySkipsLegacyInitializeWithV2Client() returns error? {
    mcpv2:StreamableHttpClient mcpClient = check new ("http://localhost:9099/recording/agentId");
    AgentIdAuthConfig auth = {baseAuthUrl: "http://localhost:9/auth", clientId: "client", redirectUri: "http://localhost/cb"};
    ToolConfig[] tools = check getPermittedMcpToolConfigs(mcpClient, {name: "MCP", version: "1.0.0"}, mcpV2Dispatcher,
            auth);
    test:assertEquals(tools.map(tool => tool.name), ["echo"]);
    test:assertEquals(recordedMethods("agentId"), ["server/discover", "tools/list"]);
}

@test:Config
function testV2ClientRunsLegacyInitializeWithoutAgentIdentity() returns error? {
    mcpv2:StreamableHttpClient mcpClient = check new ("http://localhost:9099/recording/noAuth");
    ToolConfig[] tools = check getPermittedMcpToolConfigs(mcpClient, {name: "MCP", version: "1.0.0"}, mcpV2Dispatcher);
    test:assertEquals(tools.map(tool => tool.name), ["echo"]);
    test:assertEquals(recordedMethods("noAuth"), ["server/discover", "initialize", "notifications/initialized",
            "tools/list"]);
}
