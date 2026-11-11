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

// Always returns a new cursor, like a broken server that never stops paging.
@mcpv2:StreamableHttpServiceConfig {info: {name: "Endless", version: "1.0.0"}}
service mcpv2:StreamableHttpAdvancedService /endless on modernMcpListener {
    remote isolated function onListTools(mcpv2:Cursor? cursor) returns mcpv2:ListToolsResult =>
        {tools: [], nextCursor: (cursor ?: "") + "x"};

    remote isolated function onCallTool(mcpv2:CallToolParams params) returns mcpv2:CallToolResult =>
        {content: []};
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
function testUnwrapMcpToolResultReplacesBinaryContentWithMarkers() {
    mcpv2:CallToolResult result = {
        content: [
            {'type: "text", text: "A chart"},
            {'type: "image", data: "aGk=", mimeType: "image/png"},
            {'type: "audio", data: "aGk=", mimeType: "audio/wav"},
            {'type: "resource_link", name: "report", uri: "file:///report.pdf"},
            {'type: "resource", 'resource: {uri: "file:///notes.txt", text: "Notes"}},
            {'type: "resource", 'resource: {uri: "file:///logo.png", blob: "aGk="}}
        ],
        structuredContent: {chart: "bar"}
    };
    test:assertEquals(unwrapMcpToolResult(result), "A chart\n[image: image/png]\n[audio: audio/wav]\n"
        + "[resource: file:///report.pdf]\nNotes\n[resource: file:///logo.png]");
}

@test:Config
function testUnwrapMcpToolResultReplacesBinaryContentForDeprecatedClient() {
    mcp:CallToolResult result = {content: [{'type: "image", data: "aGk=", mimeType: "image/jpeg"}]};
    test:assertEquals(unwrapMcpToolResult(result), "[image: image/jpeg]");
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
function testUnwrapMcpToolResultExplainsEmptyError() {
    mcpv2:CallToolResult result = {content: [], isError: true};
    test:assertEquals(unwrapMcpToolResult(result),
        {isError: true, content: "The tool reported an error without details."});
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
isolated function mcpV2Dispatcher(mcpv2:CallToolParams params) returns mcpv2:CallToolResult|error =>
    {content: [{'type: "text", text: params.name}]};

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

@test:Config
function testPermittedMcpToolConfigsStopsAtPageCap() returns error? {
    mcpv2:StreamableHttpClient mcpClient = check new ("http://localhost:9098/endless");
    ToolConfig[]|Error tools = getPermittedMcpToolConfigs(mcpClient, {name: "MCP", version: "1.0.0"}, mcpV2Dispatcher);
    if tools !is Error {
        test:assertFail("Expected an error for a server that never stops paging");
    }
    test:assertEquals((<error>tools.cause()).message(), "MCP server returned more than 100 pages of tools");
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

isolated function renamedParamsDispatcher(mcpv2:CallToolParams request) returns mcpv2:CallToolResult|error {
    record {}? arguments = request?.arguments;
    return {content: [{'type: "text", text: string `${request.name}: ${(arguments ?: {}).toString()}`}]};
}

isolated function contextFirstDispatcher(Context ctx, mcpv2:CallToolParams request) returns mcpv2:CallToolResult|error =>
    renamedParamsDispatcher(request);

isolated function otherParamFirstDispatcher(string? tenant, mcpv2:CallToolParams request)
        returns mcpv2:CallToolResult|error => renamedParamsDispatcher(request);

isolated function largeRefundNeedsApproval(mcpv2:CallToolParams request) returns boolean {
    record {}? arguments = request?.arguments;
    anydata amount = arguments is () ? () : arguments["amount"];
    return amount is int && amount > 100;
}

isolated class RenamedParamsMcpToolKit {
    *McpBaseToolKit;
    private final readonly & ToolConfig[] tools;

    isolated function init(RequiresApproval requiresApproval = false) {
        ToolConfig[] tools = [
            {
                name: "refund",
                description: "Issues a refund",
                parameters: {properties: {amount: {'type: INTEGER}}},
                caller: renamedParamsDispatcher,
                requiresApproval
            },
            {name: "withContext", description: "Takes a context first", caller: contextFirstDispatcher},
            {name: "withTenant", description: "Takes another parameter first", caller: otherParamFirstDispatcher}
        ];
        self.tools = tools.cloneReadOnly();
    }

    public isolated function getTools() returns ToolConfig[] => self.tools;
}

@test:Config
function testMcpDispatcherWithRenamedParameter() returns error? {
    ToolStore toolStore = check new (new RenamedParamsMcpToolKit());
    foreach string toolName in ["refund", "withContext", "withTenant"] {
        ToolOutput output = check toolStore.execute({name: toolName, arguments: {"amount": 500}});
        test:assertEquals(unwrapMcpToolResult(check output.value), string `${toolName}: {"amount":500}`);
    }
}

@test:Config
function testMcpApprovalPredicateWithRenamedParameterSkipsGate() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new HitlConditionalMockLLM({name: "refund", arguments: {"amount": 50}, id: "call-1"}),
        tools: [new RenamedParamsMcpToolKit(largeRefundNeedsApproval)]
    });
    // An unbound predicate fails safe to pausing, so running shows the arguments reached it.
    string result = check agent.run("Refund 50", "renamed-params-below-session");
    test:assertTrue(result.includes(string `refund: {"amount":50}`), result);
}

@test:Config
function testMcpApprovalPredicateWithRenamedParameterGates() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new HitlConditionalMockLLM({name: "refund", arguments: {"amount": 500}, id: "call-1"}),
        tools: [new RenamedParamsMcpToolKit(largeRefundNeedsApproval)]
    });
    string|Error result = agent.run("Refund 500", "renamed-params-above-session");
    test:assertTrue(result is ApprovalRequiredError, result is Error ? result.message() : result);
}
