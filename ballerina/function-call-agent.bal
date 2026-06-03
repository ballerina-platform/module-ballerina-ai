// Copyright (c) 2024 WSO2 LLC (http://www.wso2.com).
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

import ballerina/cache;
import ballerina/lang.regexp;
import ballerina/log;

# Function call agent. 
# This agent uses OpenAI function call API to perform the tool selection.
isolated distinct class FunctionCallAgent {
    *BaseAgent;
    # Tool store to be used by the agent
    final ToolStore toolStore;
    # LLM model instance (should be a function call model)
    final ModelProvider model;
    # The memory associated with the agent.
    final Memory memory;
    # Represents if the agent is stateless or not.
    final boolean stateless;
    # Strategy used to control how and when tools are loaded for the agent.
    final ToolLoadingStrategy toolLoadingStrategy;
    # Cache used to store and reuse authentication tokens for tool access.
    final cache:Cache tokenManager;
    # Authentication configuration used for acquiring OAuth tokens when accessing secured tools.
    final readonly & Credential? agentCredential;

    # Initialize an Agent.
    #
    # + model - LLM model instance
    # + tools - Tools to be used by the agent
    # + memory - The memory associated with the agent.
    isolated function init(ModelProvider model, (BaseToolKit|ToolConfig|FunctionTool)[] tools, cache:Cache tokenManager,
            Credential? agentCredential, Memory? memory = (), ToolLoadingStrategy toolLoadingStrategy = NO_FILTER) returns Error? {
        self.toolStore = check new (...tools);
        self.model = model;
        self.memory = memory ?: check new ShortTermMemory();
        self.stateless = memory is ();
        self.toolLoadingStrategy = toolLoadingStrategy;
        self.agentCredential = agentCredential.cloneReadOnly();
        self.tokenManager = tokenManager;
    }

    # Parse the function calling API response and extract the tool to be executed.
    #
    # + llmResponse - Raw LLM response
    # + return - A record containing the tool decided by the LLM, chat response or an error if the response is invalid
    isolated function parseLlmResponse(json llmResponse) returns LlmToolResponse|LlmChatResponse|LlmInvalidGenerationError {
        if llmResponse is string {
            return {content: llmResponse};
        }
        if llmResponse !is FunctionCall {
            return error LlmInvalidGenerationError("Invalid response", llmResponse = llmResponse);
        }
        string? name = llmResponse.name;
        if name is () {
            return error LlmInvalidGenerationError("Missing name", name = llmResponse.name, arguments = llmResponse.arguments);
        }
        return {
            name,
            arguments: llmResponse.arguments,
            id: llmResponse.id
        };
    }

    # Use LLM to decide the next tool/step based on the function calling APIs.
    #
    # + progress - Execution progress with the current query and execution history
    # + sessionId - The ID associated with the agent memory
    # + return - LLM response containing the tool or chat response (or an error if the call fails)
    isolated function selectNextTool(ExecutionProgress progress, string sessionId = DEFAULT_SESSION_ID) returns json|Error {
        ChatMessage[] messages = createFunctionCallMessages(progress);
        messages.unshift(...progress.history);
        ToolLoadingStrategy toolLoadingStrategy = self.toolLoadingStrategy;
        ChatMessage lastMessage = messages[messages.length() - 1];
        ChatCompletionFunctions[] registeredTools = from Tool tool in self.toolStore.tools.toArray()
            select {
                name: tool.name,
                description: tool.description,
                parameters: tool.variables
            };
        ChatCompletionFunctions[] filteredTools = registeredTools;
        if toolLoadingStrategy == LLM_FILTER && lastMessage is ChatUserMessage {
            ChatCompletionFunctions[]? selectedTools = lazyLoadTools(cloneMessages(messages), registeredTools, self.model);
            if selectedTools !is () {
                filteredTools = selectedTools;
            }
        }

        log:printDebug("Requesting tool selection from LLM",
                executionId = progress.executionId,
                sessionId = sessionId,
                messages = messages.toString(),
                availableTools = filteredTools.toString()
        );

        ResponseSchema? responseSchema = progress.responseSchema;
        if responseSchema is ResponseSchema {
            filteredTools.push(getStructuredOutputTool(responseSchema.schema));
        }

        // TODO: Improve handling of multiple tool calls returned by the LLM.
        // Currently, tool calls are executed sequentially in separate chat responses.
        // Update the logic to execute all tool calls together and return a single response.
        ChatAssistantMessage response = check self.model->chat(messages, filteredTools);
        FunctionCall? toolCall = getFirstToolCall(response);

        if toolCall is FunctionCall {
            if responseSchema is ResponseSchema && toolCall.name == GET_RESULTS_TOOL {
                log:printDebug("LLM returned the final answer via the structured-output tool",
                        executionId = progress.executionId,
                        sessionId = sessionId,
                        toolArguments = toolCall.arguments
                );
                return getStructuredAnswer(toolCall, responseSchema);
            }
            log:printDebug("LLM selected tool",
                    executionId = progress.executionId,
                    sessionId = sessionId,
                    toolName = toolCall.name,
                    toolArguments = toolCall.arguments
            );
            return toolCall;
        }

        log:printDebug("LLM provided chat response instead of tool call",
                executionId = progress.executionId,
                sessionId = sessionId,
                response = response?.content
        );
        return response?.content;
    }

    # Execute the agent for a given user's query.
    #
    # + query - Natural langauge commands to the agent  
    # + instruction - Instruction to the agent on how to process the query
    # + maxIter - No. of max iterations that agent will run to execute the task (default: 5)
    # + context - Context values to be used by the agent to execute the task
    # + verbose - If true, then print the reasoning steps (default: true)
    # + sessionId - The ID associated with the agent memory
    # + executionId - Unique identifier for this execution
    # + responseSchema - Schema for the expected structured final answer; when set, a final-answer tool
    # carrying this schema is exposed so the model returns its answer as a tool call
    # + return - Returns the execution steps tracing the agent's reasoning and outputs from the tools
    isolated function run(string|Prompt query, string instruction, int maxIter = 5, boolean verbose = true,
            string sessionId = DEFAULT_SESSION_ID, Context context = new, string executionId = DEFAULT_EXECUTION_ID,
            ResponseSchema? responseSchema = ())
            returns ExecutionTrace {
        Credential? & readonly agentConfig = self.agentCredential;
        string? agentId = agentConfig is Credential ? agentConfig.id : ();
        return run(self, instruction, query, maxIter, verbose, agentId, sessionId, context, executionId, responseSchema);
    }
}

# Builds the dedicated final-answer tool that carries the structured-output schema as its parameters.
#
# + parameters - JSON schema describing the expected final-answer structure
# + return - The final-answer tool definition
isolated function getStructuredOutputTool(map<json> parameters) returns ChatCompletionFunctions => {
    name: GET_RESULTS_TOOL,
    description: "Call this tool to deliver the final answer once the task is complete. " +
        "The answer must conform to the tool's parameter schema.",
    parameters
};

# Extracts the final answer from a structured-output tool call as a JSON string, unwrapping the
# synthetic `result` field added for expected return types that are not JSON objects.
#
# + toolCall - The structured-output tool call returned by the model
# + responseSchema - The schema used to build the tool, indicating whether the type was wrapped
# + return - The final answer serialized as a JSON string
isolated function getStructuredAnswer(FunctionCall toolCall, ResponseSchema responseSchema) returns string {
    map<json> arguments = toolCall.arguments ?: {};
    json value = responseSchema.isOriginallyJsonObject ? arguments : arguments[RESULT];
    return value.toJsonString();
}

isolated function createFunctionCallMessages(ExecutionProgress progress) returns ChatMessage[] {
    ChatMessage[] messages = [];
    foreach ExecutionStep step in progress.executionSteps {
        FunctionCall|error functionCall = step.llmResponse.fromJsonWithType();
        if functionCall is error {
            panic error Error("Badly formated history for function call agent", llmResponse = step.llmResponse);
        }

        messages.push({
            role: ASSISTANT,
            toolCalls: [functionCall]
        },
        {
            role: FUNCTION,
            name: functionCall.name,
            content: getObservationString(step.observation),
            id: functionCall?.id
        });
    }
    return messages;
}

isolated function modifyUserPromptWithToolsInfo(ChatUserMessage chatUserMsg, ToolInfo[] toolInfo)
returns ChatUserMessage {
    string toolsPrompt = string `

These are the tools available to you: 
${BACKTICKS} 
${toolInfo.toJsonString()}
${BACKTICKS}

Select only the tools required to complete the task and return them as a JSON array of tool names:
${BACKTICKS} 
["toolNameOne","toolNameTwo","toolNameN"]
${BACKTICKS}

If no tools are needed, return an empty array:
${BACKTICKS}
[]
${BACKTICKS}`;

    string|Prompt content = chatUserMsg.content;
    if content is string {
        content += toolsPrompt;
    } else {
        content.insertions.push(toolsPrompt);
    }

    return {role: USER, content, name: chatUserMsg.name};
}

isolated function getSelectedToolsFromAssistantMessage(ChatAssistantMessage assistantMsg) returns string[]? {
    do {
        string rawResponse = assistantMsg.content ?: "[]";
        string cleanedJson = regexp:replaceAll(check regexp:fromString("```"), rawResponse, "");
        return check cleanedJson.fromJsonStringWithType();
    } on fail error e {
        // In case of failure try to load all tools and ignore the error
        return;
    }
}

isolated function cloneMessages(ChatMessage[] messages) returns ChatMessage[] {
    ChatMessage[] clonedMessages = [];
    foreach ChatMessage msg in messages {
        if msg is ChatUserMessage {
            clonedMessages.push(cloneUserMessage(msg));
            continue;
        }
        if msg is ChatSystemMessage {
            clonedMessages.push(cloneSystemMessage(msg));
            continue;
        }
        if msg is ChatAssistantMessage|ChatFunctionMessage {
            clonedMessages.push(msg.clone());
        }
    }
    return clonedMessages;
}

isolated function cloneUserMessage(ChatUserMessage message) returns ChatUserMessage {
    string|Prompt content = message.content;
    string|Prompt clonedContent = content is string ? content
        : createPrompt(content.strings, content.insertions.cloneReadOnly());
    ChatUserMessage clonedMessage = {
        role: USER,
        content: clonedContent
    };
    if message?.name is string {
        clonedMessage.name = message?.name;
    }
    return clonedMessage;
}

isolated function cloneSystemMessage(ChatSystemMessage message) returns ChatSystemMessage {
    string|Prompt content = message.content;
    string|Prompt clonedContent = content is string ? content
        : createPrompt(content.strings, content.insertions.cloneReadOnly());
    ChatSystemMessage clonedMessage = {
        role: SYSTEM,
        content: clonedContent
    };
    if message?.name is string {
        clonedMessage.name = message?.name;
    }
    return clonedMessage;
}

isolated function lazyLoadTools(ChatMessage[] messages, ChatCompletionFunctions[] registeredTools,
        ModelProvider model) returns ChatCompletionFunctions[]? {
    ChatMessage lastMessage = messages[messages.length() - 1];
    if lastMessage !is ChatUserMessage {
        return;
    }
    ToolInfo[] toolInfo = registeredTools.'map(tool => {name: tool.name, description: tool.description});
    ChatUserMessage modifiedUserMessage = modifyUserPromptWithToolsInfo(lastMessage, toolInfo);

    // Replace the last user message with the modified one that includes the tools prompt
    _ = messages.pop();
    messages.push(modifiedUserMessage);

    ChatAssistantMessage|Error response = model->chat(messages, []);
    if response is Error {
        return;
    }

    log:printDebug(string `Calling model for lazy tool loading. Raw response: ${response.content.toString()}`);
    string[]? selectedTools = getSelectedToolsFromAssistantMessage(response);
    log:printDebug(string `Extracted tools from model response: ${selectedTools.toString()}`);

    if selectedTools is string[] {
        // Only load the tool schemas picked by the model
        return from ChatCompletionFunctions tool in registeredTools
            let string toolName = tool.name
            where selectedTools.some(selected => selected == toolName)
            select tool;
    }
    return;
}

isolated function getFirstToolCall(ChatAssistantMessage msg) returns FunctionCall? {
    FunctionCall[]? toolCalls = msg?.toolCalls;
    if toolCalls is () || toolCalls.length() == 0 {
        return;
    }
    return toolCalls[0];
}
