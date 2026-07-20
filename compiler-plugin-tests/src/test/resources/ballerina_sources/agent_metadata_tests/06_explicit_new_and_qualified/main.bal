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

import ai_tests.toolmod;

import ballerina/ai;

@ai:AgentTool
isolated function localTool(string query) returns string => "local";

isolated function configCaller(string query) returns string => "config";

// A custom agent that uses the EXPLICIT `new ai:Agent(...)` form (not the implicit `new (...)`), with a
// mix of tool entries that exercise the static name extraction:
//   - `localTool`                  -> module-level function tool (name: "localTool")
//   - `toolmod:remoteLookup`       -> a tool referenced from another module (name: "remoteLookup")
//   - `toolConfigVar`              -> a `ToolConfig` VARIABLE; the name is not statically known -> skipped
//   - `{description, name, caller}`-> inline `ToolConfig` with `name` after `description` (name: "inlineNamed")
//   - `{name: dynamicName, ...}`   -> inline `ToolConfig` with a non-literal `name` -> skipped
public isolated class ResearchAgent {
    *ai:FixedTypedAgent;

    private final ai:Agent agent;

    public function init(ai:ModelProvider model) returns error? {
        ai:ToolConfig toolConfigVar =
            {name: "fromVariable", description: "Built elsewhere.", caller: configCaller};
        string dynamicName = "computed";
        // An MCP toolkit assigned to a variable: classified as MCP_TOOLKIT, named after the variable.
        ai:McpToolKit weatherMcp = check new ("http://localhost:3000/mcp");
        self.agent = check new ai:Agent(
            systemPrompt = {role: "Researcher", instructions: "Research things."},
            model = model,
            // The memory is created inline (not an `init` parameter reference), so no `memory` entry is
            // recorded in the generated metadata.
            memory = new ai:MessageWindowChatMemory(10),
            tools = [
                localTool,
                toolmod:remoteLookup,
                toolConfigVar,
                {description: "Inline tool.", name: "inlineNamed", caller: configCaller},
                {name: dynamicName, description: "Computed name.", caller: configCaller},
                weatherMcp,
                // An MCP toolkit constructed inline (no variable): named after its type.
                check new ai:McpToolKit("http://localhost:3001/mcp")
            ]
        );
    }

    public isolated function run(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns anydata|ai:Error => self.agent.run(query, sessionId, context);

    public isolated function trace(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns ai:Trace|ai:Error => self.agent.run(query, sessionId, context);
}
