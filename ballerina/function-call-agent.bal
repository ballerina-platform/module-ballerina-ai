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
    final boolean enableLazyToolLoading;

    # Initialize an Agent.
    #
    # + model - LLM model instance
    # + tools - Tools to be used by the agent
    # + memory - The memory associated with the agent.
    isolated function init(ModelProvider model, (BaseToolKit|ToolConfig|FunctionTool)[] tools,
            Memory? memory = (), boolean enableLazyToolLoading = false) returns Error? {
        self.toolStore = check new (...tools);
        self.model = model;
        self.memory = memory ?: check new ShortTermMemory();
        self.stateless = memory is ();
        self.enableLazyToolLoading = enableLazyToolLoading;
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
        ChatMessage[]|MemoryError additionalMessages = self.memory.get(sessionId);
        if additionalMessages is MemoryError {
            log:printError("Failed to get chat messages from memory", additionalMessages);
        } else {
            messages.unshift(...additionalMessages);
        }

        ChatMessage lastMessage = messages[messages.length() - 1];
        ChatCompletionFunctions[] tools = from Tool tool in self.toolStore.tools.toArray()
            select {
                name: tool.name,
                description: tool.description,
                parameters: tool.variables
            };

        if self.enableLazyToolLoading && lastMessage is ChatUserMessage {
            ToolInfo[] toolInfo = self.toolStore.getToolsInfo();
            ChatUserMessage modifiedUserMessage = modifyUserPromptWithToolsInfo(lastMessage, toolInfo);

            // Replace the last user message with the modified one that includes the tools prompt
            _ = messages.pop();
            messages.push(modifiedUserMessage);

            ChatAssistantMessage response = check self.model->chat(messages, []);
            log:printDebug(string `Calling model for lazy tool loading. Raw response: ${response.content.toString()}`);
            string[]? selectedTools = getSelectedToolsFromAssistantMessage(response);
            log:printDebug(string `Extracted tools from model response: ${selectedTools.toString()}`);

            if selectedTools is string[] {
                // Only load the tool schemas picked by the model
                tools = from ChatCompletionFunctions tool in tools
                    let string toolName = tool.name
                    where selectedTools.some(selected => selected == toolName)
                    select tool;
            }

            // Revert last message to original
            _ = messages.pop();
            messages.push(lastMessage);
        }

        // TODO: Improve handling of multiple tool calls returned by the LLM.  
        // Currently, tool calls are executed sequentially in separate chat responses.  
        // Update the logic to execute all tool calls together and return a single response.
        ChatAssistantMessage response = check self.model->chat(messages, tools);
        FunctionCall[]? toolCalls = response?.toolCalls;
        return toolCalls is FunctionCall[] ? toolCalls[0] : response?.content;
    }

    # Execute the agent for a given user's query.
    #
    # + query - Natural langauge commands to the agent  
    # + instruction - Instruction to the agent on how to process the query
    # + maxIter - No. of max iterations that agent will run to execute the task (default: 5)
    # + context - Context values to be used by the agent to execute the task
    # + verbose - If true, then print the reasoning steps (default: true)
    # + sessionId - The ID associated with the agent memory
    # + return - Returns the execution steps tracing the agent's reasoning and outputs from the tools
    isolated function run(string query, string instruction, int maxIter = 5, boolean verbose = true,
            string sessionId = DEFAULT_SESSION_ID, Context context = new) returns ExecutionTrace {
        return run(self, instruction, query, maxIter, verbose, sessionId, context);
    }

}

isolated function createFunctionCallMessages(ExecutionProgress progress) returns ChatMessage[] {
    ChatMessage[] messages = [];
    foreach ExecutionStep step in progress.history {
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

These are the following tools available to you: 
${BACKTICKS} 
${toolInfo.toJsonString()}
${BACKTICKS}

Select only the tools needed to complete the task and return them as a JSON array of tool names:
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
