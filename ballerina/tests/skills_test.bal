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

import ballerina/file;
import ballerina/test;

const SKILLS_RESOURCES = "tests/resources/skills";
const SINGLE_SKILL_PATH = SKILLS_RESOURCES + "/single-skill";
const MULTI_SKILLS_PATH = SKILLS_RESOURCES + "/multi-skills";
const INVALID_SKILL_PATH = SKILLS_RESOURCES + "/invalid-skill";
const LENIENT_SKILL_PATH = SKILLS_RESOURCES + "/lenient-skill";
const DUPLICATE_SKILL_PATH = SKILLS_RESOURCES + "/duplicate";

final Skill & readonly inlineSkill = {
    name: "inline-skill",
    description: "An inline skill used for testing.",
    instructions: "Do inline things.",
    resources: {
        "references/notes.md": "Inline notes",
        "assets/data.json": "{}"
    }
};

@test:Config {groups: ["skills"]}
function testLoadSingleSkillDirectory() returns error? {
    map<SkillInfo> skills = check loadSkills([{path: SINGLE_SKILL_PATH}]);
    test:assertEquals(skills.keys(), ["single-skill"]);
    SkillInfo skill = skills.get("single-skill");
    test:assertEquals(skill.description, "A single skill used for testing. Use when testing skill loading.");
    test:assertTrue(skill.instructions.startsWith("# Single skill"));
    test:assertEquals(skill.resources, ["assets/template.csv", "references/guide.md"]);
    test:assertTrue(skill.baseDir is string);
}

@test:Config {groups: ["skills"]}
function testLoadParentDirectorySkipsInvalidAndNonSkillDirectories() returns error? {
    map<SkillInfo> skills = check loadSkills([{path: MULTI_SKILLS_PATH}]);
    test:assertEquals(skills.keys(), ["skill-a", "skill-b"]);
    test:assertEquals(skills.get("skill-a").resources, []);
}

@test:Config {groups: ["skills"]}
function testInvalidSingleSkillDirectoryFails() {
    map<SkillInfo>|Error skills = loadSkills([{path: INVALID_SKILL_PATH}]);
    if skills !is Error {
        test:assertFail("Expected an error for a skill without a description");
    }
    test:assertTrue(skills.message().includes("non-empty 'description'"), skills.message());
}

@test:Config {groups: ["skills"]}
function testMissingSkillPathFails() {
    map<SkillInfo>|Error skills = loadSkills([{path: SKILLS_RESOURCES + "/does-not-exist"}]);
    if skills !is Error {
        test:assertFail("Expected an error for a missing skill path");
    }
    test:assertTrue(skills.message().includes("does not exist"), skills.message());
}

@test:Config {groups: ["skills"]}
function testEmptySkillDirectoryLoadsNoSkills() returns error? {
    string emptyDir = check file:createTempDir();
    map<SkillInfo> skills = check loadSkills([{path: emptyDir}]);
    test:assertEquals(skills.length(), 0);
    check file:remove(emptyDir);
}

@test:Config {groups: ["skills"]}
function testDuplicateSkillNamesKeepFirst() returns error? {
    map<SkillInfo> skills = check loadSkills([{path: MULTI_SKILLS_PATH}, {path: DUPLICATE_SKILL_PATH}]);
    test:assertEquals(skills.keys(), ["skill-a", "skill-b"]);
    test:assertEquals(skills.get("skill-a").description, "The first skill in a directory of skills.");
}

@test:Config {groups: ["skills"]}
function testSpecViolationsAreLenient() returns error? {
    map<SkillInfo> skills = check loadSkills([{path: LENIENT_SKILL_PATH}]);
    test:assertEquals(skills.keys(), ["Lenient_Name"]);
}

@test:Config {groups: ["skills"]}
function testLoadInlineSkill() returns error? {
    map<SkillInfo> skills = check loadSkills([inlineSkill]);
    SkillInfo skill = skills.get("inline-skill");
    test:assertEquals(skill.instructions, "Do inline things.");
    test:assertEquals(skill.resources, ["assets/data.json", "references/notes.md"]);
    test:assertTrue(skill.baseDir is ());
}

@test:Config {groups: ["skills"]}
function testInlineSkillWithEmptyNameFails() {
    map<SkillInfo>|Error skills = loadSkills([{name: " ", description: "A skill", instructions: "Do things."}]);
    if skills !is Error {
        test:assertFail("Expected an error for an inline skill with an empty name");
    }
    test:assertTrue(skills.message().includes("must not be empty"), skills.message());
}

@test:Config {groups: ["skills"], dataProvider: invalidSkillMdData}
function testParseInvalidSkillMd(string content, string expectedMessage) {
    SkillMetadata|Error metadata = parseSkillMd(content);
    if metadata !is Error {
        test:assertFail("Expected an error for invalid SKILL.md content");
    }
    test:assertTrue(metadata.message().includes(expectedMessage), metadata.message());
}

function invalidSkillMdData() returns string[][] => [
    ["# No frontmatter", "must start with YAML frontmatter"],
    ["---\nname: unclosed\ndescription: Never closed", "is not closed"],
    ["---\n- a\n- b\n---\nBody", "must be a YAML mapping"],
    ["---\nname: [unclosed\n---\nBody", "is not valid YAML"],
    ["---\nname: 1\ndescription: Numeric name\n---\nBody", "must be strings"],
    ["---\nname: no-description\n---\nBody", "non-empty 'description'"],
    ["---\ndescription: No name\n---\nBody", "must not be empty"],
    ["---\nname: ''\ndescription: Empty name\n---\nBody", "must not be empty"]
];

@test:Config {groups: ["skills"]}
function testParseSkillMd() returns error? {
    SkillMetadata metadata = check parseSkillMd("\r\n---\r\nname: my-skill\r\ndescription: Does things\r\n---\r\n\r\nLine 1\r\nLine 2\r\n");
    test:assertEquals(metadata, {name: "my-skill", description: "Does things", instructions: "Line 1\nLine 2"});
}

@test:Config {groups: ["skills"]}
function testSkillCatalogEscapesMetadata() returns error? {
    map<SkillInfo> skills = check loadSkills([{path: MULTI_SKILLS_PATH}]);
    string catalog = buildSkillCatalog(skills);
    test:assertTrue(catalog.startsWith("# Skills\nSkills contain the policies and procedures you must follow."));
    test:assertTrue(catalog.includes("<available_skills>\n  <skill>\n    <name>skill-a</name>"));
    test:assertTrue(catalog.includes(
        "<description>Handles &lt;tags&gt; &amp; \"quotes\" in descriptions.</description>"));
    test:assertTrue(catalog.endsWith("</skill>\n</available_skills>"));
}

@test:Config {groups: ["skills"]}
function testActivateLocalSkill() returns error? {
    SkillsToolKit toolKit = new (check loadSkills([{path: SINGLE_SKILL_PATH}]));
    string content = check toolKit.activateSkill("single-skill");
    test:assertTrue(content.startsWith("<skill_content name=\"single-skill\">\n# Single skill\n"));
    test:assertTrue(content.endsWith(string `</skill_content>

<skill_resources>
  <resource>assets/template.csv</resource>
  <resource>references/guide.md</resource>
</skill_resources>`));
}

@test:Config {groups: ["skills"]}
function testActivateSkillWithoutResources() returns error? {
    SkillsToolKit toolKit = new (check loadSkills([{path: MULTI_SKILLS_PATH}]));
    string content = check toolKit.activateSkill("skill-a");
    test:assertEquals(content, "<skill_content name=\"skill-a\">\nInstructions for skill A.\n</skill_content>");
}

@test:Config {groups: ["skills"]}
function testActivateUnknownSkill() returns error? {
    SkillsToolKit toolKit = new (check loadSkills([{path: MULTI_SKILLS_PATH}]));
    string|Error content = toolKit.activateSkill("unknown");
    if content !is Error {
        test:assertFail("Expected an error for an unknown skill");
    }
    test:assertEquals(content.message(), "Skill 'unknown' not found. Available skills: skill-a, skill-b");
}

@test:Config {groups: ["skills"]}
function testReadLocalSkillResource() returns error? {
    SkillsToolKit toolKit = new (check loadSkills([{path: SINGLE_SKILL_PATH}]));
    test:assertEquals(check toolKit.readSkillResource("single-skill", "references/guide.md"),
        "# Guide\n\nFollow the guide.\n");
    test:assertEquals(check toolKit.readSkillResource("single-skill", "assets/template.csv"), "name,amount\n");
}

@test:Config {groups: ["skills"]}
function testReadInlineSkillResource() returns error? {
    SkillsToolKit toolKit = new (check loadSkills([inlineSkill]));
    test:assertEquals(check toolKit.readSkillResource("inline-skill", "references/notes.md"), "Inline notes");
}

@test:Config {groups: ["skills"], dataProvider: rejectedResourceData}
function testRejectedSkillResource(string skillName, string resourcePath, string expectedMessage) returns error? {
    SkillsToolKit toolKit = new (check loadSkills([{path: SINGLE_SKILL_PATH}, inlineSkill]));
    string|Error content = toolKit.readSkillResource(skillName, resourcePath);
    if content !is Error {
        test:assertFail(string `Expected '${resourcePath}' to be rejected`);
    }
    test:assertTrue(content.message().includes(expectedMessage), content.message());
}

function rejectedResourceData() returns string[][] => [
    ["unknown", "references/guide.md", "Skill 'unknown' not found"],
    ["single-skill", "SKILL.md", "must start with 'references/' or 'assets/'"],
    ["single-skill", "references/../SKILL.md", "must not contain '..'"],
    ["single-skill", "references/..\\SKILL.md", "must not contain '..'"],
    ["single-skill", "references/nested/ignored.md", "is not available in skill 'single-skill'"],
    ["single-skill", "references/missing.md", "is not available in skill 'single-skill'"],
    ["inline-skill", "references/missing.md", "is not available in skill 'inline-skill'"]
];

@test:Config {groups: ["skills"]}
function testSystemPromptWithoutSkillsIsUnchanged() {
    test:assertEquals(getFomatedSystemPrompt({role: "Role", instructions: "Instructions"}),
        "# Role  \nRole  \n\n# Instructions  \nInstructions\n");
}

@test:Config {groups: ["skills"]}
function testAgentWithSkills() returns error? {
    SkillsMockLLM model = new;
    Agent agent = check new (
        systemPrompt = {role: "Skills Agent", instructions: "Use skills"},
        model = model,
        skills = [{path: SINGLE_SKILL_PATH}]
    );
    Trace trace = check agent.run("Use the single skill", td = Trace);

    test:assertEquals(trace.tools.map(tool => tool.name), [ACTIVATE_SKILL_TOOL, READ_SKILL_RESOURCE_TOOL]);
    string systemPrompt = model.getSystemPrompt();
    test:assertTrue(systemPrompt.includes("# Instructions  \nUse skills\n\n# Skills\n"), systemPrompt);
    test:assertTrue(systemPrompt.includes("<name>single-skill</name>"), systemPrompt);

    ChatAssistantMessage|ChatFunctionMessage|Error activation = trace.iterations[0].output[0];
    if activation !is ChatFunctionMessage {
        test:assertFail("Expected the first iteration to activate the skill");
    }
    test:assertEquals(activation.name, ACTIVATE_SKILL_TOOL);
    test:assertTrue((activation.content ?: "").startsWith("<skill_content name=\"single-skill\">"));

    ChatAssistantMessage|Error output = trace.output;
    if output !is ChatAssistantMessage {
        test:assertFail("Expected a final answer");
    }
    test:assertEquals(output.content, "Skill activated");
}

@test:Config {groups: ["skills"]}
function testAgentWithoutSkillsAddsNothing() returns error? {
    SkillsMockLLM model = new;
    Agent agent = check new (
        systemPrompt = {role: "Plain Agent", instructions: "No skills"},
        model = model,
        tools = [searchTool]
    );
    Trace trace = check agent.run("Hello", td = Trace);

    test:assertEquals(trace.tools.map(tool => tool.name), ["Search"]);
    test:assertEquals(model.getSystemPrompt(), "# Role  \nPlain Agent  \n\n# Instructions  \nNo skills\n");
}

@test:Config {groups: ["skills"]}
function testAgentWithEmptySkillsAddsNothing() returns error? {
    SkillsMockLLM model = new;
    Agent agent = check new (
        systemPrompt = {role: "Plain Agent", instructions: "No skills"},
        model = model,
        skills = []
    );
    Trace trace = check agent.run("Hello", td = Trace);

    test:assertEquals(trace.tools.length(), 0);
    test:assertFalse(model.getSystemPrompt().includes("# Skills"));
}

@test:Config {groups: ["skills"]}
function testUserToolClashingWithSkillToolFails() {
    Agent|Error agent = new (
        systemPrompt = {role: "Agent", instructions: "Instructions"},
        model = new SkillsMockLLM(),
        tools = [{name: ACTIVATE_SKILL_TOOL, description: "Clashes with the skill tool", caller: clashingTool}],
        skills = [inlineSkill]
    );
    if agent !is Error {
        test:assertFail("Expected agent initialization to fail on a duplicate tool name");
    }
    test:assertTrue(agent.message().includes("duplicate tool name"), agent.message());
}

@test:Config {groups: ["skills"]}
function testAgentWithInvalidSkillSourceFails() {
    Agent|Error agent = new (
        systemPrompt = {role: "Agent", instructions: "Instructions"},
        model = new SkillsMockLLM(),
        skills = [{path: SKILLS_RESOURCES + "/does-not-exist"}]
    );
    if agent !is Error {
        test:assertFail("Expected agent initialization to fail for a missing skill path");
    }
    test:assertTrue(agent.message().includes("does not exist"), agent.message());
}

isolated function clashingTool() returns string => "clash";

// Activates the `single-skill` skill when skill tools are available, then answers once a tool result
// is in the history. Records the system prompt it receives so tests can assert on it.
isolated client class SkillsMockLLM {
    *ModelProvider;

    private string systemPrompt = "";

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [],
            string? stop = ()) returns ChatAssistantMessage|Error {
        if messages is ChatMessage[] {
            foreach ChatMessage message in messages {
                if message is ChatSystemMessage {
                    lock {
                        self.systemPrompt = message.content.toString();
                    }
                }
            }
        }
        if messages is ChatMessage[] && messages[messages.length() - 1] is ChatFunctionMessage {
            return {role: ASSISTANT, content: "Skill activated"};
        }
        if tools.some(tool => tool.name == ACTIVATE_SKILL_TOOL) {
            return {
                role: ASSISTANT,
                toolCalls: [{name: ACTIVATE_SKILL_TOOL, arguments: {name: "single-skill"}, id: "call-1"}]
            };
        }
        return {role: ASSISTANT, content: "No skills available"};
    }

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error = external;

    isolated function getSystemPrompt() returns string {
        lock {
            return self.systemPrompt;
        }
    }
}

@test:Config {groups: ["skills"]}
function testActivateSkillEscapesNameAttribute() returns error? {
    SkillsToolKit toolKit = new (check loadSkills([{name: "a\"b", description: "Quoted name", instructions: "Body"}]));
    test:assertEquals(check toolKit.activateSkill("a\"b"), "<skill_content name=\"a&quot;b\">\nBody\n</skill_content>");
}
