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

@ai:AgentTool
isolated function someTool(string query) returns string => "ok";

final ai:FunctionTool[] sharedTools = [someTool];

// A local class-level annotation, to verify the plugin skips non-`AgentMetadata` annotations already on
// the class and still appends its own.
public annotation Labelled on class;

// The `tools` argument is a variable reference, not a list literal, so the tools cannot be read
// statically. The annotation is still attached, with an empty tools list.
public isolated class DynamicToolsAgent {
    *ai:FixedReturnAgentType;

    private final ai:Agent agent;

    public function init(ai:ModelProvider model) returns error? {
        string toolSource = "dynamically supplied";
        self.agent = check new (
            // The instructions template has an interpolation, so the system prompt cannot be resolved
            // statically and must be omitted from the generated metadata.
            systemPrompt = {role: "Dynamic", instructions: string `Use ${toolSource} tools.`},
            model = model,
            tools = sharedTools
        );
    }

    public isolated function run(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns anydata|ai:Error => self.agent.run(query, sessionId, context);

    public isolated function trace(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns ai:Trace|ai:Error => self.agent.run(query, sessionId, context);
}

// A custom agent that already carries another class-level annotation: the plugin must leave it in place
// and still append its own `@ai:AgentMetadata`.
@Labelled
public isolated class LabelledAgent {
    *ai:FixedReturnAgentType;

    private final ai:Agent agent;

    public function init(ai:ModelProvider model) returns error? {
        self.agent = check new (
            systemPrompt = {role: "Labelled", instructions: "Do work."},
            model = model,
            tools = [someTool]
        );
    }

    public isolated function run(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns anydata|ai:Error => self.agent.run(query, sessionId, context);

    public isolated function trace(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns ai:Trace|ai:Error => self.agent.run(query, sessionId, context);
}

// A custom agent implemented directly, WITHOUT composing an `ai:Agent` and without an `init` method.
// It is still a discoverable agent definition, so it gets an annotation with an empty tools list.
public isolated class StaticAnswerAgent {
    *ai:FixedReturnAgentType;

    public isolated function run(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns anydata|ai:Error => "static answer";

    public isolated function trace(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns ai:Trace|ai:Error => error("trace is not supported");
}
