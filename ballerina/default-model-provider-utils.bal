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

import ai.intelligence;

import ballerina/constraint;
import ballerina/data.jsondata;
import ballerina/lang.array;
import ballerina/lang.runtime;

type ResponseSchema record {|
    map<json> schema;
    boolean isOriginallyJsonObject = true;
|};

type DocumentContentPart TextContentPart|ImageContentPart;

type TextContentPart record {|
    readonly "text" 'type = "text";
    string text;
|};

type ImageContentPart record {|
    readonly "image_url" 'type = "image_url";
    record {|string url;|} image_url;
|};

const JSON_CONVERSION_ERROR = "FromJsonStringError";
const CONVERSION_ERROR = "ConversionError";
const ERROR_MESSAGE = "Error occurred while attempting to parse the response from the " +
    "LLM as the expected type. Retrying and/or validating the prompt could fix the response.";
const RESULT = "result";
const GET_RESULTS_TOOL = "getResults";
const FUNCTION = "function";
const NO_RELEVANT_RESPONSE_FROM_THE_LLM = "No relevant response from the LLM";

isolated function generateJsonObjectSchema(map<json> schema) returns ResponseSchema {
    string[] supportedMetaDataFields = ["$schema", "$id", "$anchor", "$comment", "title", "description"];

    if schema["type"] == "object" {
        return {schema};
    }

    map<json> updatedSchema = map from var [key, value] in schema.entries()
        where supportedMetaDataFields.indexOf(key) is int
        select [key, value];

    updatedSchema["type"] = "object";
    map<json> content = map from var [key, value] in schema.entries()
        where supportedMetaDataFields.indexOf(key) !is int
        select [key, value];

    updatedSchema["properties"] = {[RESULT]: content};

    return {schema: updatedSchema, isOriginallyJsonObject: false};
}

isolated function parseResponseAsType(map<json> resp,
        typedesc<anydata> expectedResponseTypedesc, boolean isOriginallyJsonObject) returns anydata|error {
    if !isOriginallyJsonObject {
        map<json> respContent = check resp.fromJsonWithType();
        anydata|error result = trap respContent[RESULT].fromJsonWithType(expectedResponseTypedesc);
        if result is error {
            return handleParseResponseError(result);
        }
        return result;
    }

    anydata|error result = resp.fromJsonWithType(expectedResponseTypedesc);
    if result is error {
        return handleParseResponseError(result);
    }
    return result;
}

isolated function getExpectedResponseSchema(typedesc<anydata> expectedResponseTypedesc) returns ResponseSchema|Error {
    // Restricted at compile-time for now.
    typedesc<json> td = checkpanic expectedResponseTypedesc.ensureType();
    return generateJsonObjectSchema(check generateJsonSchemaForTypedescAsJson(td));
}

isolated function getGetResultsToolChoice() returns intelligence:ChatCompletionNamedToolChoice => {
    'type: FUNCTION,
    'function: {
        name: GET_RESULTS_TOOL
    }
};

isolated function getGetResultsTool(map<json> parameters) returns intelligence:ChatCompletionTool[]|error =>
    [
    {
        'type: FUNCTION,
        'function: {
            name: GET_RESULTS_TOOL,
            parameters: check parameters.cloneWithType(),
            description: "Tool to call with the response from a large language model (LLM) for a user prompt."
        }
    }
];

isolated function generateChatCreationContent(Prompt prompt) returns DocumentContentPart[]|Error {
    string[] & readonly strings = prompt.strings;
    anydata[] insertions = prompt.insertions;
    DocumentContentPart[] contentParts = [];
    string accumulatedTextContent = "";

    if strings.length() > 0 {
        accumulatedTextContent += strings[0];
    }

    foreach int i in 0 ..< insertions.length() {
        anydata insertion = insertions[i];
        string str = strings[i + 1];

        if insertion is Document|Chunk {
            addTextContentPart(buildTextContentPart(accumulatedTextContent), contentParts);
            accumulatedTextContent = "";
            check addDocumentContentPart(insertion, contentParts);
        } else if insertion is (Document|Chunk)[] {
            addTextContentPart(buildTextContentPart(accumulatedTextContent), contentParts);
            accumulatedTextContent = "";
            foreach Document|Chunk doc in insertion {
                check addDocumentContentPart(doc, contentParts);
            }
        } else {
            accumulatedTextContent += insertion.toString();
        }
        accumulatedTextContent += str;
    }

    addTextContentPart(buildTextContentPart(accumulatedTextContent), contentParts);
    return contentParts;
}

isolated function addDocumentContentPart(Document|Chunk doc, DocumentContentPart[] contentParts) returns Error? {
    if doc is TextDocument|TextChunk {
        return addTextContentPart(buildTextContentPart(doc.content), contentParts);
    } else if doc is ImageDocument {
        return contentParts.push(check buildImageContentPart(doc));
    }
    return error("Only text and image documents are supported.");
}

isolated function addTextContentPart(TextContentPart? contentPart, DocumentContentPart[] contentParts) {
    if contentPart is TextContentPart {
        return contentParts.push(contentPart);
    }
}

isolated function buildTextContentPart(string content) returns TextContentPart? {
    if content.length() == 0 {
        return;
    }

    return {
        'type: "text",
        text: content
    };
}

isolated function buildImageContentPart(ImageDocument doc) returns ImageContentPart|Error => {
    image_url: {
        url: check buildImageUrl(doc.content, doc.metadata?.mimeType)
    }
};

isolated function buildImageUrl(Url|byte[] content, string? mimeType) returns string|Error {
    if content is Url {
        Url|constraint:Error validationRes = constraint:validate(content);
        if validationRes is error {
            return error(validationRes.message(), validationRes.cause());
        }
        return content;
    }

    return string `data:${mimeType ?: "image/*"};base64,${check getBase64EncodedString(content)}`;
}

isolated function getBase64EncodedString(byte[] content) returns string|Error {
    string|error binaryContent = array:toBase64(content);
    if binaryContent is error {
        return error("Failed to convert byte array to string: " + binaryContent.message() + ", " +
                        binaryContent.detail().toBalString());
    }
    return binaryContent;
}

isolated function handleParseResponseError(error chatResponseError) returns error {
    string message = chatResponseError.message();
    if message.includes(JSON_CONVERSION_ERROR) || message.includes(CONVERSION_ERROR) {
        return error(ERROR_MESSAGE, chatResponseError);
    }
    return chatResponseError;
}

isolated function generateLlmResponse(intelligence:Client llmClient, decimal temperature,
        GeneratorConfig generatorConfig, Prompt prompt,
        typedesc<json> expectedResponseTypedesc) returns anydata|Error {
    DocumentContentPart[] content = check generateChatCreationContent(prompt);
    ResponseSchema responseSchema = check getExpectedResponseSchema(expectedResponseTypedesc);
    intelligence:ChatCompletionTool[]|error tools = getGetResultsTool(responseSchema.schema);
    if tools is error {
        return error("Error in generated schema: " + tools.message());
    }

    intelligence:CreateChatCompletionRequest request = {
        messages: [{role: USER, "content": content}],
        tools,
        toolChoice: getGetResultsToolChoice(),
        temperature
    };

    [int, decimal] [count, interval] = check getRetryConfigValues(generatorConfig);

    return getLlMResponse(llmClient, request, expectedResponseTypedesc, responseSchema.isOriginallyJsonObject,
            count, interval);
}

isolated function getLlMResponse(intelligence:Client llmClient,
        intelligence:CreateChatCompletionRequest request,
        typedesc<anydata> expectedResponseTypedesc,
        boolean isOriginallyJsonObject, int retryCount, decimal retryInterval) returns anydata|Error {
    intelligence:CreateChatCompletionResponse|error response = llmClient->/chat/completions.post(request);
    if response is error {
        return error("LLM call failed: " + response.message(), detail = response.detail(), cause = response.cause());
    }

    record {
        *intelligence:ChatCompletionChoiceCommon;
        @jsondata:Name {value: "content_filter_results"}
        intelligence:ContentFilterChoiceResults contentFilterResults?;
        intelligence:ChatCompletionResponseMessage message?;
    }[] choices = response.choices;

    if choices.length() == 0 {
        return error("No completion choices");
    }

    intelligence:ChatCompletionResponseMessage? message = choices[0].message;
    intelligence:ChatCompletionMessageToolCall[]? toolCalls = message?.toolCalls;
    if toolCalls is () || toolCalls.length() == 0 {
        return error(NO_RELEVANT_RESPONSE_FROM_THE_LLM);
    }

    intelligence:ChatCompletionMessageToolCall tool = toolCalls[0];
    intelligence:ChatCompletionMessageToolCall_function func = tool.'function;
    map<json>|error arguments = func.arguments.fromJsonStringWithType();
    if arguments is error {
        return error(NO_RELEVANT_RESPONSE_FROM_THE_LLM);
    }

    intelligence:ChatCompletionRequestMessage[] history = request.messages;
    string toolId = tool.id;
    string functionName = func.name;
    history.push({
        role: ASSISTANT,
        "tool_calls": tool
    });

    anydata|error result = handleResponseWithExpectedType(arguments, isOriginallyJsonObject,
            typeof response, expectedResponseTypedesc);
    if result is error && retryCount > 0 {
        string|error repairMessage = getRepairMessage(result, toolId, functionName);
        if repairMessage is error {
            return error("Failed to generate a valid response: " + repairMessage.message());
        }

        history.push({
            role: USER,
            "content": repairMessage
        });
        runtime:sleep(retryInterval);

        return getLlMResponse(llmClient, request, expectedResponseTypedesc, isOriginallyJsonObject,
                retryCount - 1, retryInterval);
    }

    if result is anydata {
        return result;
    }

    return error LlmInvalidGenerationError(string `Invalid value returned from the LLM Client, expected: '${
            expectedResponseTypedesc.toBalString()}', found '${result.toBalString()}'`);
}

isolated function handleResponseWithExpectedType(map<json> arguments, boolean isOriginallyJsonObject,
        typedesc responseType, typedesc<anydata> expectedResponseTypedesc) returns anydata|error {
    anydata res = check parseResponseAsType(arguments, expectedResponseTypedesc, isOriginallyJsonObject);
    return res.ensureType(expectedResponseTypedesc);
}

isolated function getRepairMessage(error e, string toolId, string functionName) returns string|error {
    error? cause = e.cause();
    if cause is () {
        return e;
    }

    return string `The tool call with ID '${toolId}' for the function '${functionName}' failed.
        Error: ${cause.toString()}
        You must correct the function arguments based on this error and respond with a valid tool call.`;
}
