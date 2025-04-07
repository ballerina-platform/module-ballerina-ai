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

import ballerina/log;

# Function call agent. 
# This agent uses OpenAI function call API to perform the tool selection.
public isolated distinct client class FunctionCallAgent {
    *BaseAgent;
    # Tool store to be used by the agent
    final ToolStore toolStore;
    # LLM model instance (should be a function call model)
    final ModelProvider model;
    # The memory associated with the agent.
    final Memory memory;
    # Represents if the agent is stateless or not.
    final boolean stateless;

    # Initialize an Agent.
    #
    # + model - LLM model instance
    # + tools - Tools to be used by the agent
    # + memory - The memory associated with the agent.
    public isolated function init(ModelProvider model, (BaseToolKit|ToolConfig|FunctionTool)[] tools,
            Memory? memory = new MessageWindowChatMemory()) returns Error? {
        self.toolStore = check new (...tools);
        self.model = model;
        self.memory = memory is Memory ? memory : new MessageWindowChatMemory();
        self.stateless = memory is ();
    }

    # Parse the function calling API response and extract the tool to be executed.
    #
    # + llmResponse - Raw LLM response
    # + return - A record containing the tool decided by the LLM, chat response or an error if the response is invalid
    public isolated function parseLlmResponse(json llmResponse) returns LlmToolResponse|LlmChatResponse|LlmInvalidGenerationError {
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
        string? stringArgs = llmResponse.arguments;
        map<json>|error? arguments = ();
        if stringArgs is string {
            arguments = stringArgs.fromJsonStringWithType();
        }
        if arguments is error {
            return error LlmInvalidGenerationError("Invalid arguments", arguments, name = llmResponse.name, arguments = stringArgs);
        }

        return {
            name,
            arguments,
            id: llmResponse.id
        };
    }

    # Use LLM to decide the next tool/step based on the function calling APIs.
    #
    # + progress - Execution progress with the current query and execution history
    # + sessionId - The ID associated with the agent memory
    # + return - LLM response containing the tool or chat response (or an error if the call fails)
    public isolated function selectNextTool(ExecutionProgress progress, string sessionId = DEFAULT_SESSION_ID) returns json|LlmError {
        ChatMessage[] messages = createFunctionCallMessages(progress);
        ChatMessage[]|MemoryError additionalMessages = self.memory.get(sessionId);
        if additionalMessages is MemoryError {
            log:printError("Failed to get chat messages from memory", additionalMessages);
        } else {
            messages.unshift(...additionalMessages);
        }

        // TODO: Improve handling of multiple tool calls returned by the LLM.  
        // Currently, tool calls are executed sequentially in separate chat responses.  
        // Update the logic to execute all tool calls together and return a single response.
        ChatAssistantMessage response = check self.model->chat(messages,
        from Tool tool in self.toolStore.tools.toArray()
        select {
            name: tool.name,
            description: tool.description,
            parameters: tool.variables
        });
        FunctionCall[]? toolCalls = response?.toolCalls;
        return toolCalls is FunctionCall[] ? toolCalls[0] : response?.content;
    }

    # Execute the agent for a given user's query.
    #
    # + query - Natural langauge commands to the agent  
    # + maxIter - No. of max iterations that agent will run to execute the task (default: 5)
    # + context - Context values to be used by the agent to execute the task
    # + verbose - If true, then print the reasoning steps (default: true)
    # + sessionId - The ID associated with the agent memory
    # + return - Returns the execution steps tracing the agent's reasoning and outputs from the tools
    isolated remote function run(string query, int maxIter = 5, string|map<json> context = {}, boolean verbose = true,
            string sessionId = DEFAULT_SESSION_ID)
        returns record {|(ExecutionResult|ExecutionError)[] steps; string answer?;|} {
        return run(self, query, maxIter, context, verbose, sessionId);
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
