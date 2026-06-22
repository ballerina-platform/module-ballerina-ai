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

import ballerina/ai as intelligence;

@intelligence:AgentTool
isolated function answerMath(string question) returns string => "42";

// The `ballerina/ai` import is aliased: the enum members inside the generated `agentMetadata` must use the
// alias (`intelligence:FUNCTION_TOOL`), while `@display` itself stays unqualified.
public isolated class MathAgent {
    *intelligence:FixedTypedAgent;

    private final intelligence:Agent agent;

    public function init(intelligence:ModelProvider model) returns error? {
        self.agent = check new (
            // The instructions use a string template without interpolations; it must still be resolved.
            systemPrompt = {role: "Math Tutor", instructions: string `Answer math questions.`},
            model = model,
            tools = [answerMath]
        );
    }

    public isolated function run(string|intelligence:Prompt query, string sessionId = "default-session",
            intelligence:Context context = new) returns anydata|intelligence:Error =>
        self.agent.run(query, sessionId, context);

    public isolated function trace(string|intelligence:Prompt query, string sessionId = "default-session",
            intelligence:Context context = new) returns intelligence:Trace|intelligence:Error =>
        self.agent.run(query, sessionId, context);
}
