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

// https: //opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-agent-spans/#create-agent-span
# Represents a tracing span for creating an agent.
public isolated distinct class CreateAgentSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    # Initializes a new agent creation span for the given agent name.
    # 
    # + agentName - The name of the agent being created
    isolated function init(string agentName) {
        self.baseSpan = new (string `${CREATE_AGENT} ${agentName}`);
        self.addTag(OPERATION_NAME, CREATE_AGENT);
        self.addTag(PROVIDER_NAME, "Ballerina");
        self.addTag(AGENT_NAME, agentName);
    }

    # Records the agent ID assigned after creation.
    # 
    # + agentId - The agent identifier
    public isolated function addId(string agentId) {
        self.addTag(AGENT_ID, agentId);
    }

    # Records system instruction of the agent.
    # 
    # + instructions - The system instructions string
    public isolated function addSystemInstructions(string instructions) {
        self.addTag(SYSTEM_INSTRUCTIONS, instructions);
    }

    // Not mandated by spec
    # Records the tools used by the agent.
    # 
    # + tools - Tools used by the agent
    public isolated function addTools(json tools) {
        self.addTag(AGENT_TOOLS, tools);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    # Closes the agent creation span and records its final status.
    # 
    # + err - Optional error that indicates if the operation failed
    public isolated function close(error? err = ()) {
        self.baseSpan.close(err);
    }
}

// https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-agent-spans/#invoke-agent-span
# Represents a tracing span for invoking an agent.
public isolated distinct class InvokeAgentSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    # Initializes a new agent invocation span for the given agent name.
    # 
    # + agentName - The name of the agent being invoked
    isolated function init(string agentName) {
        self.baseSpan = new (string `${INVOKE_AGENT} ${agentName}`);
        self.addTag(OPERATION_NAME, INVOKE_AGENT);
        self.addTag(PROVIDER_NAME, "Ballerina");
        self.addTag(AGENT_NAME, agentName);
    }

    # Records the agent ID of the invocation.
    # 
    # + agentId - The agent identifier
    public isolated function addId(string agentId) {
        self.addTag(AGENT_ID, agentId);
    }

    # Records system instruction of the agent.
    # 
    # + instruction - The system instruction
    public isolated function addSystemInstruction(string instruction) {
        self.addTag(SYSTEM_INSTRUCTIONS, instruction);
    }

    # Records the session ID of the invocation.
    # 
    # + sessionId - The session/conversation identifier
    public isolated function addSessionId(string sessionId) {
        self.addTag(CONVERSATION_ID, sessionId);
    }

    # Records the input query of the agent invocation.
    # 
    # + query - The input query string
    public isolated function addInput(string query) {
        self.addTag(INPUT_MESSAGES, query);
    }

    # Records the output of the agent invocation.
    # 
    # + outputType - The output type
    # + output - The output messages
    public isolated function addOutput(OutputType outputType, json output) {
        self.addTag(OUTPUT_TYPE, outputType);
        self.addTag(OUTPUT_MESSAGES, output);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    # Closes the agent invocation span and records its final status.
    # 
    # + err - Optional error that indicates if the operation failed
    public isolated function close(error? err = ()) {
        self.baseSpan.close(err);
    }
}

// https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-spans/#execute-tool-span
# Represents a tracing span for executing a tool.
public isolated distinct class ExecuteToolSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    # Initializes a new tool execution span for the given tool name.
    # 
    # + toolName - The name of the tool being executed
    isolated function init(string toolName) {
        self.baseSpan = new (string `${EXECUTE_TOOL} ${toolName}`);
        self.addTag(OPERATION_NAME, EXECUTE_TOOL);
        self.addTag(TOOL_NAME, toolName);
    }

    # Records the tool call ID of the execution.
    # 
    # + toolCallId - The tool call identifier
    public isolated function addId(string|int toolCallId) {
        self.addTag(TOOL_CALL_ID, toolCallId);
    }

    # Records the tool description of the execution.
    # 
    # + description - The tool description string
    public isolated function addDescription(string description) {
        self.addTag(TOOL_DESCRIPTION, description);
    }

    # Records the tool type of the execution.
    # 
    # + toolType - The tool type
    public isolated function addType(ToolType toolType) {
        self.addTag(TOOL_TYPE, toolType);
    }

    // Not mandated by spec
    # Records arguments of the tool execution.
    # 
    # + arguments - The tool arguments
    public isolated function addArguments(json arguments) {
        self.addTag(TOOL_ARGUMENTS, arguments);
    }

    // Not mandated by spec
    # Records output of the tool execution.
    # 
    # + output - The output produced by the tool
    public isolated function addOutput(anydata output) {
        self.addTag(TOOL_OUTPUT, output);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    # Closes the tool execution span and records its final status.
    # 
    # + err - Optional error that indicates if the operation failed
    public isolated function close(error? err = ()) {
        self.baseSpan.close(err);
    }
}
