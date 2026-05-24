// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
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
import ballerina/test;

// When the expected return type is a non-string, non-`Trace` `anydata` type, the agent appends the
// target JSON schema to the system prompt and binds its final answer into that type within the same run.

type WeatherReport record {|
    string city;
    int temperature;
    string condition;
|};

// A reusable custom agent definition: a subtype of `ai:FixedReturnAgentType` that composes an `ai:Agent`
// and declares a fixed `WeatherReport` return type.
isolated class WeatherAgent {
    *ai:FixedReturnAgentType;

    private final ai:Agent agent;

    function init() returns error? {
        self.agent = check new (
            systemPrompt = {role: "Weather Reporter", instructions: "Report the weather."},
            model = model,
            tools = [sum]
        );
    }

    public isolated function run(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns WeatherReport|ai:Error =>
        self.agent.run(query, sessionId, context);

    public isolated function trace(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns ai:Trace|ai:Error =>
        self.agent.run(query, sessionId, context);
}

@test:Config
function testAgentRunWithRecordReturn() returns error? {
    WeatherReport report = check agent.run("Give me the weather report.");
    test:assertEquals(report, {city: "Colombo", temperature: 32, condition: "Sunny"});
}

@test:Config
function testAgentRunWithIntReturn() returns error? {
    int result = check agent.run("Tell me your lucky number.");
    test:assertEquals(result, 7);
}

// The agent accepts a `Prompt` (template) query in addition to a plain string.
@test:Config
function testAgentRunWithPromptQuery() returns error? {
    string location = "Colombo";
    WeatherReport report = check agent.run(`Give me the weather report for ${location}.`);
    test:assertEquals(report, {city: "Colombo", temperature: 32, condition: "Sunny"});
}

@test:Config
function testAgentRunStripsMarkdownCodeFences() returns error? {
    WeatherReport report = check agent.run("Give me the fenced json weather data.");
    test:assertEquals(report, {city: "Kandy", temperature: 25, condition: "Cloudy"});
}

// A `string` return type must keep the original behaviour: the answer is returned verbatim.
@test:Config
function testAgentRunWithStringReturnIsUnchanged() returns error? {
    string result = check agent.run("What is the sum of the following numbers 78 90 45 23 8?");
    test:assertEquals(result, "Answer is: 244");
}

// The custom `*ai:FixedReturnAgentType` definition returns its declared structured type.
@test:Config
function testFixedReturnAgentDefinition() returns error? {
    WeatherAgent weatherAgent = check new;
    WeatherReport report = check weatherAgent.run("Give me the weather report.");
    test:assertEquals(report, {city: "Colombo", temperature: 32, condition: "Sunny"});
}

// The same definition surfaces the full execution trace via its `trace` method.
@test:Config
function testFixedReturnAgentTrace() returns error? {
    WeatherAgent weatherAgent = check new;
    ai:Trace trace = check weatherAgent.trace("Give me the weather report.");
    test:assertEquals(trace.userMessage.content, "Give me the weather report.");
    test:assertTrue(trace.id.length() > 0);
}

// Regression: the schema instruction is appended to the system prompt, which the memory layer keeps in a
// single per-session slot that is overwritten each call. So no matter how many structured runs share a
// session, the schema must never accumulate into more than one stored message (the original leak appended
// it to the query, duplicating it across the accumulating user-message history).
@test:Config
function testStructuredRunDoesNotDuplicateSchemaInMemory() returns error? {
    ai:MessageWindowChatMemory memory = new;
    ai:Agent dupAgent = check new (
        systemPrompt = {role: "Weather Reporter", instructions: "Report the weather."},
        model = model,
        tools = [sum],
        memory = memory
    );
    string session = "structured-dup-session";

    // Two structured runs on the same session — each appends the schema to the system prompt.
    WeatherReport _ = check dupAgent.run("Give me the weather report.", sessionId = session);
    WeatherReport _ = check dupAgent.run("Give me the weather report.", sessionId = session);

    int schemaCount = 0;
    foreach ai:ChatMessage message in check memory.get(session) {
        if message.content.toString().includes("strictly conforms") {
            schemaCount += 1;
        }
    }
    test:assertTrue(schemaCount == 1,
            "The structured-output schema instruction must not be duplicated across structured runs");
}
