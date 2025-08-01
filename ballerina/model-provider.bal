// Copyright (c) 2023 WSO2 LLC (http://www.wso2.com).
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

import ai.intelligence;
import ballerina/jballerina.java;

# Roles for the chat messages.
public enum ROLE {
    SYSTEM = "system",
    USER = "user",
    ASSISTANT = "assistant",
    FUNCTION = "function"
}

# User chat message record.
public type ChatUserMessage record {|
    # Role of the message
    USER role;
    # Content of the message
    string|Prompt content;
    # An optional name for the participant
    # Provides the model information to differentiate between participants of the same role
    string name?;
|};

# System chat message record.
public type ChatSystemMessage record {|
    # Role of the message
    SYSTEM role;
    # Content of the message
    string|Prompt content;
    # An optional name for the participant
    # Provides the model information to differentiate between participants of the same role
    string name?;
|};

# Assistant chat message record.
public type ChatAssistantMessage record {|
    # Role of the message
    ASSISTANT role;
    # The contents of the assistant message
    # Required unless `tool_calls` or `function_call` is specified
    string? content = ();
    # An optional name for the participant
    # Provides the model information to differentiate between participants of the same role
    string name?;
    # The function calls generated by the model, such as function calls
    FunctionCall[]? toolCalls = ();
|};

# Function message record.
public type ChatFunctionMessage record {|
    # Role of the message
    FUNCTION role;
    # Content of the message
    string? content = ();
    # Name of the function when the message is a function call
    string name;
    # Identifier for the tool call
    string id?;
|};

# Chat message record.
public type ChatMessage ChatUserMessage|ChatSystemMessage|ChatAssistantMessage|ChatFunctionMessage;

# Function definitions for function calling API.
public type ChatCompletionFunctions record {|
    # Name of the function
    string name;
    # Description of the function
    string description;
    # Parameters of the function
    map<json> parameters?;
|};

# Function call record
public type FunctionCall record {|
    # Name of the function
    string name;
    # Arguments of the function
    map<json>? arguments = {};
    # Identifier for the tool call
    string id?;
|};

# Raw template type for prompts.
public type Prompt object {
    *object:RawTemplate;
    # The fixed string parts of the template.
    public string[] & readonly strings;
    # The insertions in the template. 
    # Array of values to be inserted into the template, can be anydata, Document, or Chunk types
    public (anydata|Document|Document[]|Chunk|Chunk[])[] insertions;
};

# Represents an extendable client for interacting with an AI model.
public type ModelProvider distinct isolated client object {
    # Sends a chat request to the model with the given messages and tools.
    # + messages - List of chat messages or a user message
    # + tools - Tool definitions to be used for the tool call
    # + stop - Stop sequence to stop the completion
    # + return - Function to be called, chat response or an error in-case of failures
    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [], string? stop = ())
        returns ChatAssistantMessage|Error;
    
    # Sends a chat request to the model and generates a value that belongs to the type
    # corresponding to the type descriptor argument.
    #
    # + prompt - The prompt to use in the chat request
    # + td - Type descriptor specifying the expected return type format
    # + return - Generates a value that belongs to the type, or an error if generation fails
    isolated remote function generate(Prompt prompt, @display {label: "Expected type"} typedesc<anydata> td = <>) returns td|Error;
};

# Represents configuratations of WSO2 provider.
#
# + serviceUrl - The URL for the WSO2 AI service
# + accessToken - Access token for accessing WSO2 AI service
public type Wso2ProviderConfig record {|
    string serviceUrl;
    string accessToken;
|};

const DEFAULT_TEMPERATURE = 0.7d;

# WSO2 model provider implementation that provides chat completion capabilities using WSO2's AI services.
public isolated distinct client class Wso2ModelProvider {
    *ModelProvider;
    private final intelligence:Client llmClient;
    private final decimal temperature;

    # Initializes a new `WSO2ModelProvider` instance.
    #
    # + serviceUrl - The base URL of WSO2 intelligence API endpoint
    # + accessToken - The access token for authenticating API requests
    # + temperature - The temperature for controlling randomness in the model's output  
    # + connectionConfig - Additional HTTP connection configuration
    # + return - `nil` on success, or an `ai:Error` if initialization fails
    public isolated function init(@display {label: "Service URL"} string serviceUrl,
            @display {label: "Access Token"} string accessToken,
            @display {label: "Temperature"} decimal temperature = DEFAULT_TEMPERATURE,
            @display {label: "Connection Configuration"} *ConnectionConfig connectionConfig) returns Error? {
        intelligence:ConnectionConfig intelligenceConfig = {
            auth: {
                token: accessToken
            },
            httpVersion: connectionConfig.httpVersion,
            http1Settings: connectionConfig.http1Settings,
            http2Settings: connectionConfig.http2Settings,
            timeout: connectionConfig.timeout,
            forwarded: connectionConfig.forwarded,
            poolConfig: connectionConfig.poolConfig,
            cache: connectionConfig.cache,
            compression: connectionConfig.compression,
            circuitBreaker: connectionConfig.circuitBreaker,
            retryConfig: connectionConfig.retryConfig,
            responseLimits: connectionConfig.responseLimits,
            secureSocket: connectionConfig.secureSocket,
            proxy: connectionConfig.proxy,
            validation: connectionConfig.validation
        };
        intelligence:Client|error llmClient = new (config = intelligenceConfig, serviceUrl = serviceUrl);
        if llmClient is error {
            return error Error("Failed to initialize Wso2ModelProvider", llmClient);
        }
        self.llmClient = llmClient;
        self.temperature = temperature;
    }

    # Sends a chat request to the model with the given messages and tools.
    #
    # + messages - List of chat messages or a user message
    # + tools - Tool definitions to be used for the tool call
    # + stop - Stop sequence to stop the completion
    # + return - Function to be called, chat response or an error in-case of failures
    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools, string? stop = ())
    returns ChatAssistantMessage|Error {
        intelligence:CreateChatCompletionRequest request = {
            stop,
            messages: self.mapToChatCompletionRequestMessage(messages),
            temperature: self.temperature
        };
        if tools.length() > 0 {
            request.functions = tools;
        }
        intelligence:CreateChatCompletionResponse|error response = self.llmClient->/chat/completions.post(request);
        if response is error {
            return error LlmConnectionError("Error while connecting to the model", response);
        }
        if response.choices.length() == 0 {
            return error LlmInvalidResponseError("Empty response from the model when using function call API");
        }
        intelligence:ChatCompletionResponseMessage? message = response.choices[0].message;
        ChatAssistantMessage chatAssistantMessage = {role: ASSISTANT, content: message?.content};
        intelligence:ChatCompletionFunctionCall? functionCall = message?.functionCall;
        if functionCall is intelligence:ChatCompletionFunctionCall {
            chatAssistantMessage.toolCalls = [check self.mapToFunctionCall(functionCall)];
        }
        return chatAssistantMessage;
    }


    # Sends a chat request to the model and generates a value that belongs to the type
    # corresponding to the type descriptor argument.
    # 
    # + prompt - The prompt to use in the chat messages
    # + td - Type descriptor specifying the expected return type format
    # + return - Generates a value that belongs to the type, or an error if generation fails
    isolated remote function generate(Prompt prompt, @display {label: "Expected type"} typedesc<anydata> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.stdlib.ai.wso2.Generator"
    } external;

    private isolated function mapToChatCompletionRequestMessage(ChatMessage[]|ChatUserMessage messages)
    returns intelligence:ChatCompletionRequestMessage[] {
        if messages is ChatUserMessage {
            return [self.mapUserOrSystemMessage(messages)];
        }
        intelligence:ChatCompletionRequestMessage[] chatCompletionRequestMessages = [];
        foreach ChatMessage message in messages {
            if message is ChatAssistantMessage {
                intelligence:ChatCompletionRequestMessage assistantMessage = {role: ASSISTANT};
                FunctionCall[]? toolCalls = message.toolCalls;
                if toolCalls is FunctionCall[] && toolCalls.length() > 0 {
                    assistantMessage["function_call"] = {
                        name: toolCalls[0].name,
                        arguments: toolCalls[0].arguments.toJsonString()
                    };
                }
                if message?.content is string {
                    assistantMessage["content"] = message?.content;
                }
                chatCompletionRequestMessages.push(assistantMessage);
                continue;
            }
            if message is ChatUserMessage|ChatSystemMessage {
                intelligence:ChatCompletionRequestMessage transformedMessage = self.mapUserOrSystemMessage(message);
                if message.name is string {
                    transformedMessage["name"] = message.name;
                }
                chatCompletionRequestMessages.push(transformedMessage);
                continue;
            }
            chatCompletionRequestMessages.push(message);
        }
        return chatCompletionRequestMessages;
    }

    private isolated function mapToFunctionCall(intelligence:ChatCompletionFunctionCall functionCall)
    returns FunctionCall|LlmError {
        do {
            json jsonArgs = check functionCall.arguments.fromJsonString();
            map<json>? arguments = check jsonArgs.cloneWithType();
            return {name: functionCall.name, arguments};
        } on fail error e {
            return error LlmError("Invalid or malformed arguments received in function call response.", e);
        }
    }

    private isolated function mapUserOrSystemMessage(ChatUserMessage|ChatSystemMessage message)
    returns intelligence:ChatCompletionRequestMessage => {
        role: message.role,
        "content": getChatMessageStringContent(message.content)
    };
}
