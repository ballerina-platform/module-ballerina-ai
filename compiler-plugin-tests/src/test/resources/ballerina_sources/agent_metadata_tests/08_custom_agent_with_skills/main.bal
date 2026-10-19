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

const string SKILLS_DIR = "./skills";

final ai:Skill toneSkill = {
    name: "tone",
    description: "Tone guidelines for replies.",
    instructions: "Be polite and concise."
};

final ai:LocalSkillSource sharedSkills = {path: "./shared-skills"};

isolated function skillsDir() returns string => "./dynamic-skills";

// Lists local skill sources and inline skills: literal entries are recorded with their path or name,
// and variables with their variable name. An entry whose path is not statically known is skipped.
public isolated class SupportAgent {
    *ai:FixedTypedAgent;

    private final ai:Agent agent;

    public function init(ai:ModelProvider model) returns error? {
        self.agent = check new (
            systemPrompt = {role: "Support Agent", instructions: "Help customers."},
            model = model,
            skills = [
                {path: SKILLS_DIR},
                sharedSkills,
                toneSkill,
                {name: "escalation", description: "When to escalate.", instructions: "Escalate refunds over $500."},
                {path: skillsDir()}
            ]
        );
    }

    public isolated function run(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns anydata|ai:Error => self.agent.run(query, sessionId, context);

    public isolated function trace(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns ai:Trace|ai:Error => self.agent.run(query, sessionId, context);
}
