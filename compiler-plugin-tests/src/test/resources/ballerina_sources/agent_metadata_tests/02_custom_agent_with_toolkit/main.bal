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

import ballerina/ai;

const string SALES_ROLE = "Sales Agent";

@ai:AgentTool
isolated function getDiscounts(string category) returns string => "10%";

isolated function listItems(string category) returns string => "items";

// A toolkit's tools are only known at runtime (via `getTools()`), so they cannot be listed statically.
isolated class DiscountsToolKit {
    *ai:BaseToolKit;

    public isolated function getTools() returns ai:ToolConfig[] =>
        [{name: "listItems", description: "Lists the items on discount.", caller: listItems}];
}

// Mixes a toolkit with a function tool: only the statically identifiable function tool should be
// listed in the generated `@ai:AgentMetadata` annotation.
public isolated class SalesAgent {
    *ai:FixedReturnAgentType;

    private final ai:Agent agent;

    public function init(ai:ModelProvider model) returns error? {
        DiscountsToolKit toolKit = new;
        self.agent = check new (
            // The role references a `const`; it must be resolved through the semantic model.
            systemPrompt = {role: SALES_ROLE, instructions: "Promote sales."},
            model = model,
            tools = [toolKit, getDiscounts]
        );
    }

    public isolated function run(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns anydata|ai:Error => self.agent.run(query, sessionId, context);

    public isolated function trace(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns ai:Trace|ai:Error => self.agent.run(query, sessionId, context);
}

// Uses only a toolkit: the annotation should still be attached, with an empty tools list.
public isolated class ToolKitOnlyAgent {
    *ai:FixedReturnAgentType;

    private final ai:Agent agent;

    public function init(ai:ModelProvider model) returns error? {
        DiscountsToolKit toolKit = new;
        self.agent = check new (
            systemPrompt = {role: "Sales Agent", instructions: "Promote sales."},
            model = model,
            tools = [toolKit]
        );
    }

    public isolated function run(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns anydata|ai:Error => self.agent.run(query, sessionId, context);

    public isolated function trace(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns ai:Trace|ai:Error => self.agent.run(query, sessionId, context);
}
