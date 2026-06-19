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

// A module-level function tool with a `@display` annotation (read via the symbol API).
@display {label: "Coordinate Speakers", iconPath: "speakers.png"}
@ai:AgentTool
isolated function coordinateSpeakers(string topic) returns string => "speakers coordinated";

// Used as the caller of an inline `ai:ToolConfig`; the tool name comes from the config's `name` field.
isolated function customSearch(string query) returns string => "search result";

// A custom agent definition: the compiler plugin should record the `agentMetadata` field within `@display`
// listing the tools passed to the composed `ai:Agent` — the object method tool, the module-level
// function tool, and the inline `ai:ToolConfig` (by its explicit `name`).
public isolated class SchedulerAgent {
    *ai:FixedReturnAgentType;

    private final ai:Agent agent;

    // Both the model and the memory are injected through `init` parameters, so the generated metadata
    // records each parameter's name: modelProvider: {parameterName: "model"}, memory: {parameterName:
    // "chatMemory"}.
    public function init(ai:Memory chatMemory, ai:ModelProvider model) returns error? {
        self.agent = check new (
            systemPrompt = {role: "Event Schedule Manager", instructions: "Organize the event schedule."},
            model = model,
            memory = chatMemory,
            tools = [
                self.createSchedule,
                coordinateSpeakers,
                {name: "searchTool", description: "Searches the web.", caller: customSearch}
            ]
        );
    }

    public isolated function run(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns anydata|ai:Error => self.agent.run(query, sessionId, context);

    public isolated function trace(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns ai:Trace|ai:Error => self.agent.run(query, sessionId, context);

    // An object method used as a tool, with a `@display` annotation (read syntactically for `self.` methods).
    @display {label: "Create Schedule"}
    @ai:AgentTool
    isolated function createSchedule(string eventName) returns string => "scheduled";
}
