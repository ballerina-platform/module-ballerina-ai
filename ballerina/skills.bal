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
import ballerina/io;
import ballerina/jballerina.java;
import ballerina/log;
import ballerina/data.yaml;

const SKILL_FILE_NAME = "SKILL.md";
const REFERENCES_DIR = "references";
const ASSETS_DIR = "assets";
const FRONTMATTER_DELIMITER = "---";
const MAX_SKILL_NAME_LENGTH = 64;
const MAX_SKILL_DESCRIPTION_LENGTH = 1024;
const ACTIVATE_SKILL_TOOL = "__activate_skill__";
const READ_SKILL_RESOURCE_TOOL = "__read_skill_resource__";

const SKILL_CATALOG_INSTRUCTIONS = "Skills contain the policies and procedures you must follow. " +
    "If a request relates to any skill listed below, you MUST call the `" + ACTIVATE_SKILL_TOOL +
    "` tool with that skill's name\n" +
    "before answering or making any decision, and follow its instructions exactly. " +
    "Do not rely on your own assumptions in place of a skill.\n" +
    "Read a skill's resources with the `" + READ_SKILL_RESOURCE_TOOL + "` tool when its instructions refer to them.";

# Represents a skill, or a directory of skills, on the local file system in the Agent Skills format.
public type LocalSkillSource record {|
    # Path to a skill directory (a directory that contains a `SKILL.md` file), or to a directory
    # whose immediate sub-directories are skill directories.
    # A relative path is resolved against the current working directory of the running program.
    string path;
|};

# Represents a skill defined inline in code, without a file system.
public type Skill record {|
    # The unique name of the skill
    string name;
    # A short description of what the skill does and when it should be used
    string description;
    # The full instructions returned when the skill is activated
    string instructions;
    # Optional resources, keyed by their relative path (e.g. `references/api.md`), with the content as the value
    map<string> resources = {};
|};

# Represents a source of skills for an agent.
public type SkillSource LocalSkillSource|Skill;

# A skill loaded and validated by the agent.
type SkillInfo readonly & record {|
    # The unique name of the skill
    string name;
    # The description shown in the skill catalog
    string description;
    # The body returned when the skill is activated
    string instructions;
    # The real path of the skill directory, for local skills
    string? baseDir;
    # The resource contents, for inline skills
    map<string>? inlineResources;
    # The relative paths of the resources the skill exposes
    string[] resources;
|};

type ParsedSkillMd record {|
    string name;
    string description;
    string instructions;
|};

# Loads and validates the skills from the given sources.
#
# + skillSources - The skill sources configured for the agent
# + return - The loaded skills keyed by name, or an `Error` if a source cannot be loaded
isolated function loadSkills(SkillSource[] skillSources) returns map<SkillInfo> & readonly|Error {
    map<SkillInfo> skills = {};
    foreach SkillSource skillSource in skillSources {
        SkillInfo[] loadedSkills = skillSource is LocalSkillSource
            ? check loadLocalSkills(skillSource.path) : [check loadInlineSkill(skillSource)];
        foreach SkillInfo skill in loadedSkills {
            if skills.hasKey(skill.name) {
                log:printWarn(string `Skipping duplicate skill '${skill.name}': a skill with the same name is already loaded`);
                continue;
            }
            skills[skill.name] = skill;
        }
    }
    return skills.cloneReadOnly();
}

isolated function loadLocalSkills(string path) returns SkillInfo[]|Error {
    do {
        string absPath = check file:getAbsolutePath(path);
        if !check file:test(absPath, file:EXISTS) {
            return error Error(string `Skill path '${path}' does not exist`);
        }
        if !check file:test(absPath, file:IS_DIR) {
            return error Error(string `Skill path '${path}' is not a directory`);
        }
        if check isSkillDir(absPath) {
            return [check loadLocalSkill(absPath)];
        }

        string[] subDirs = from file:MetaData entry in check file:readDir(absPath)
            where entry.dir
            order by entry.absPath
            select entry.absPath;
        SkillInfo[] skills = [];
        foreach string subDir in subDirs {
            if !check isSkillDir(subDir) {
                continue;
            }
            SkillInfo|Error skill = loadLocalSkill(subDir);
            if skill is Error {
                log:printWarn(string `Skipping skill: ${skill.message()}`);
                continue;
            }
            skills.push(skill);
        }
        if skills.length() == 0 {
            log:printWarn(string `No skills found in '${path}'`);
        }
        return skills;
    } on fail error err {
        return err is Error ? err : error Error(string `Failed to load skills from '${path}'`, err);
    }
}

isolated function isSkillDir(string dir) returns boolean|error =>
    file:test(check file:joinPath(dir, SKILL_FILE_NAME), file:EXISTS);

isolated function loadLocalSkill(string dir) returns SkillInfo|Error {
    do {
        string content = check io:fileReadString(check file:joinPath(dir, SKILL_FILE_NAME));
        ParsedSkillMd {name, description, instructions} = check parseSkillMd(content);
        warnSpecViolations(name, description, check file:basename(dir));
        string[] resources = check listLocalResources(dir);
        return {
            name,
            description,
            instructions,
            baseDir: check getRealPath(dir),
            inlineResources: (),
            resources: resources.cloneReadOnly()
        };
    } on fail error err {
        return error Error(string `Invalid skill at '${dir}': ${err.message()}`, err);
    }
}

isolated function loadInlineSkill(Skill skill) returns SkillInfo|Error {
    check validateSkillMetadata(skill.name, skill.description);
    warnSpecViolations(skill.name, skill.description, ());
    return {
        name: skill.name,
        description: skill.description,
        instructions: skill.instructions,
        baseDir: (),
        inlineResources: skill.resources.cloneReadOnly(),
        resources: skill.resources.keys().sort().cloneReadOnly()
    };
}

# Parses the content of a `SKILL.md` file into its frontmatter metadata and body.
#
# + content - The content of the `SKILL.md` file
# + return - The skill metadata and instructions, or an `Error` if the content is invalid
isolated function parseSkillMd(string content) returns ParsedSkillMd|Error {
    string[] lines = re `\r?\n`.split(content.trim());
    if lines[0].trim() != FRONTMATTER_DELIMITER {
        return error Error("SKILL.md must start with YAML frontmatter delimited by '---' lines");
    }
    int? closingLine = ();
    foreach int i in 1 ..< lines.length() {
        if lines[i].trim() == FRONTMATTER_DELIMITER {
            closingLine = i;
            break;
        }
    }
    if closingLine is () {
        return error Error("SKILL.md frontmatter is not closed with a '---' line");
    }

    json|yaml:Error frontmatter = yaml:parseString(string:'join("\n", ...lines.slice(1, closingLine)));
    if frontmatter is yaml:Error {
        return error Error("SKILL.md frontmatter is not valid YAML", frontmatter);
    }
    if frontmatter !is map<json> {
        return error Error("SKILL.md frontmatter must be a YAML mapping");
    }
    json name = frontmatter["name"] ?: "";
    json description = frontmatter["description"] ?: "";
    if name !is string || description !is string {
        return error Error("'name' and 'description' in SKILL.md frontmatter must be strings");
    }
    check validateSkillMetadata(name, description);
    return {
        name,
        description,
        instructions: string:'join("\n", ...lines.slice(closingLine + 1)).trim()
    };
}

isolated function validateSkillMetadata(string name, string description) returns Error? {
    if name.trim().length() == 0 {
        return error Error("Skill 'name' must not be empty");
    }
    if description.trim().length() == 0 {
        return error Error(string `Skill '${name}' must have a non-empty 'description'`);
    }
}

# Logs a warning for each Agent Skills specification constraint the skill violates.
# These constraints are checked leniently, so a violating skill is still loaded.
#
# + name - The skill name
# + description - The skill description
# + dirName - The name of the skill directory, for local skills
isolated function warnSpecViolations(string name, string description, string? dirName) {
    if name.length() > MAX_SKILL_NAME_LENGTH || !re `[a-z0-9]+(-[a-z0-9]+)*`.isFullMatch(name) {
        log:printWarn(string `Skill name '${name}' does not follow the Agent Skills naming rules: ` +
            string `1-${MAX_SKILL_NAME_LENGTH} lowercase letters, digits, or hyphens, ` +
            "with no leading, trailing, or consecutive hyphens");
    }
    if dirName is string && dirName != name {
        log:printWarn(string `Skill name '${name}' does not match its directory name '${dirName}'`);
    }
    if description.length() > MAX_SKILL_DESCRIPTION_LENGTH {
        log:printWarn(string `Description of skill '${name}' exceeds ${MAX_SKILL_DESCRIPTION_LENGTH} characters`);
    }
}

isolated function listLocalResources(string skillDir) returns string[]|error {
    string[] resources = [];
    foreach string resourceDir in [REFERENCES_DIR, ASSETS_DIR] {
        string resourceDirPath = check file:joinPath(skillDir, resourceDir);
        if !check file:test(resourceDirPath, file:IS_DIR) {
            continue;
        }
        foreach file:MetaData entry in check file:readDir(resourceDirPath) {
            if !entry.dir {
                resources.push(string `${resourceDir}/${check file:basename(entry.absPath)}`);
            }
        }
    }
    return resources.sort();
}

# Builds the skill catalog that is added to the system prompt.
#
# + skills - The loaded skills
# + return - The skill catalog section of the system prompt
isolated function buildSkillCatalog(map<SkillInfo> skills) returns string {
    string catalog = string `# Skills
${SKILL_CATALOG_INSTRUCTIONS}

<available_skills>`;
    foreach SkillInfo skill in skills {
        catalog += string `
  <skill>
    <name>${escapeXmlText(skill.name)}</name>
    <description>${escapeXmlText(skill.description)}</description>
  </skill>`;
    }
    return catalog + "\n</available_skills>";
}

isolated function escapeXmlText(string value) returns string {
    string escaped = re `&`.replaceAll(value, "&amp;");
    escaped = re `<`.replaceAll(escaped, "&lt;");
    return re `>`.replaceAll(escaped, "&gt;");
}

isolated function escapeXmlAttribute(string value) returns string =>
    re `"`.replaceAll(escapeXmlText(value), "&quot;");

# Provides the built-in tools that load skill instructions and resources on demand.
isolated class SkillsToolKit {
    *BaseToolKit;
    private final map<SkillInfo> & readonly skills;
    private final ToolConfig[] & readonly tools;

    isolated function init(map<SkillInfo> & readonly skills) {
        self.skills = skills;
        ToolConfig[] tools = [
            {
                name: ACTIVATE_SKILL_TOOL,
                description: "Loads the full instructions of a skill listed in the available skills, " +
                    "along with the list of resources the skill provides.",
                parameters: {
                    'type: "object",
                    properties: {
                        name: {'type: "string", description: "The name of the skill to activate"}
                    },
                    required: ["name"]
                },
                caller: self.activateSkill
            },
            {
                name: READ_SKILL_RESOURCE_TOOL,
                description: "Reads a resource file listed by an activated skill.",
                parameters: {
                    'type: "object",
                    properties: {
                        skillName: {'type: "string", description: "The name of the skill that owns the resource"},
                        resourcePath: {
                            'type: "string",
                            description: "The path of the resource as listed by the skill, e.g. 'references/guide.md'"
                        }
                    },
                    required: ["skillName", "resourcePath"]
                },
                caller: self.readSkillResource
            }
        ];
        self.tools = tools.cloneReadOnly();
    }

    public isolated function getTools() returns ToolConfig[] => self.tools;

    # Returns the instructions and the resource list of a skill.
    #
    # + name - The name of the skill to activate
    # + return - The skill content, or an `Error` if the skill does not exist
    isolated function activateSkill(string name) returns string|Error {
        SkillInfo skill = check self.getSkill(name);
        string content = string `<skill_content name="${escapeXmlAttribute(skill.name)}">
${skill.instructions}
</skill_content>`;
        if skill.resources.length() == 0 {
            return content;
        }
        content += "\n\n<skill_resources>";
        foreach string resourcePath in skill.resources {
            content += string `
  <resource>${escapeXmlText(resourcePath)}</resource>`;
        }
        return content + "\n</skill_resources>";
    }

    # Returns the content of a resource listed by a skill.
    #
    # + skillName - The name of the skill that owns the resource
    # + resourcePath - The path of the resource relative to the skill directory
    # + return - The resource content, or an `Error` if the resource cannot be read
    isolated function readSkillResource(string skillName, string resourcePath) returns string|Error {
        SkillInfo skill = check self.getSkill(skillName);
        if !resourcePath.startsWith(REFERENCES_DIR + "/") && !resourcePath.startsWith(ASSETS_DIR + "/") {
            return error Error(string `Resource path '${resourcePath}' must start with '${REFERENCES_DIR}/' or '${ASSETS_DIR}/'`);
        }
        if re `[/\\]`.split(resourcePath).indexOf("..") !is () {
            return error Error(string `Resource path '${resourcePath}' must not contain '..'`);
        }
        if skill.resources.indexOf(resourcePath) is () {
            return error Error(string `Resource '${resourcePath}' is not available in skill '${skillName}'. ` +
                string `Available resources: ${string:'join(", ", ...skill.resources)}`);
        }

        map<string>? inlineResources = skill.inlineResources;
        if inlineResources is map<string> {
            return inlineResources.get(resourcePath);
        }
        string? baseDir = skill.baseDir;
        if baseDir is () {
            return error Error(string `Resource '${resourcePath}' is not available in skill '${skillName}'`);
        }
        do {
            string realPath = check getRealPath(check file:joinPath(baseDir, resourcePath));
            if (check file:relativePath(baseDir, realPath)).startsWith("..") {
                return error Error(string `Resource '${resourcePath}' resolves outside the skill directory`);
            }
            string|error content = string:fromBytes(check io:fileReadBytes(realPath));
            if content is error {
                return error Error(string `Resource '${resourcePath}' of skill '${skillName}' is a binary file ` +
                    "and cannot be returned as text");
            }
            return content;
        } on fail error err {
            return err is Error ? err
                : error Error(string `Failed to read resource '${resourcePath}' of skill '${skillName}'`, err);
        }
    }

    private isolated function getSkill(string name) returns SkillInfo|Error {
        SkillInfo? skill = self.skills[name];
        if skill is () {
            return error Error(string `Skill '${name}' not found. ` +
                string `Available skills: ${string:'join(", ", ...self.skills.keys())}`);
        }
        return skill;
    }
}

isolated function getRealPath(string path) returns string|Error = @java:Method {
    'class: "io.ballerina.stdlib.ai.SkillUtils"
} external;
