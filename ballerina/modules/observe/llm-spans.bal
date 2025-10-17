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

// https://opentelemetry.io/docs/specs/semconv/gen-ai/non-normative/examples-llm-calls/
# Represents an LLM-specific tracing span for LLM calls.
public type LlmSpan distinct isolated object {
    *AiSpan;

    # Records the provider name used for the request.
    #
    # + providerName - The name of the AI provider/service (for example: `openai`)
    public isolated function addProvider(string providerName);

    # Records the temperature setting used for the request.
    #
    # + temperature - The temperature value controlling randomness
    public isolated function addTemperature(float|decimal temperature);

    # Records the input messages payload for the request.
    #
    # + messages - The input messages sent to the model
    public isolated function addInputMessages(json messages);

    # Records the output messages payload produced by the model.
    #
    # + messages - The output messages returned by the model
    public isolated function addOutputMessages(json messages);

    # Records the model name used for the response.
    #
    # + modelName - The model identifier/name used to generate the response (for example: `gpt-40-2024`)
    public isolated function addResponseModel(string modelName);

    # Records the response identifier assigned by the provider.
    #
    # + id - The provider-assigned response identifier
    public isolated function addResponseId(string|int id);

    # Records the count of input tokens consumed by the request.
    #
    # + count - Number of input tokens consumed
    public isolated function addInputTokenCount(int count);

    # Records the count of output tokens produced by the model.
    #
    # + count - Number of output tokens produced
    public isolated function addOutputTokenCount(int count);

    # Records the finish reason(s) returned by the model.
    #
    # + reason - A finish reason string or an array of reasons returned by the model
    public isolated function addFinishReason(string|string[] reason);

    # Records the response output type
    #
    # + outputType - The output type describing the response format
    public isolated function addOutputType(OutputType outputType);

    # Records one or more stop sequences supplied to the model
    #
    # + stopSequence - A single stop sequence or an array of stop sequences
    public isolated function addStopSequence(string|string[] stopSequence);

    // Not mandated by spec
    # Records the tools schema send to the model
    #
    # + tools - An array of tool schemas sent the the model
    public isolated function addTools(json[] tools);
};

# Chat-specific LLM span implementation for chat operations.
public isolated distinct class ChatSpan {
    *LlmSpan;
    private final BaseSpanImp baseSpan;

    isolated function init(string modelName) {
        self.baseSpan = new (string `${CHAT} ${modelName}`);
        self.addTag(OPERATION_NAME, CHAT);
        self.addTag(REQUEST_MODEL, modelName);
    }

    # Records the provider name used for the request.
    #
    # + providerName - The name of the AI provider/service (for example: `openai`)
    public isolated function addProvider(string providerName) {
        self.addTag(PROVIDER_NAME, providerName);
    }

    # Records the temperature setting used for the request.
    #
    # + temperature - The temperature value controlling randomness
    public isolated function addTemperature(float|decimal temperature) {
        self.addTag(TEMPERATURE, temperature);
    }

    # Records the input messages payload for the request.
    #
    # + messages - The input messages sent to the model
    public isolated function addInputMessages(json messages) {
        self.addTag(INPUT_MESSAGES, messages);
    }

    # Records the output messages payload produced by the model.
    #
    # + messages - The output messages returned by the model
    public isolated function addOutputMessages(json messages) {
        self.addTag(OUTPUT_MESSAGES, messages);
    }

    # Records the model name used for the response.
    #
    # + modelName - The model identifier/name used to generate the response (for example: `gpt-40-2024`)
    public isolated function addResponseModel(string modelName) {
        self.addTag(RESPONSE_MODEL, modelName);
    }

    # Records the tools schema send to the model.
    #
    # + tools - An array of tool schemas sent the the model
    public isolated function addTools(json[] tools) {
        self.addTag(INPUT_TOOLS, tools);
    }

    # Records the response identifier assigned by the provider.
    #
    # + id - The provider-assigned response identifier
    public isolated function addResponseId(string|int id) {
        self.addTag(RESPONSE_ID, id);
    }

    # Records the count of input tokens consumed by the request.
    #
    # + count - Number of input tokens consumed
    public isolated function addInputTokenCount(int count) {
        self.addTag(INPUT_TOKENS, count);
    }

    # Records the count of output tokens produced by the response.
    #
    # + count - Number of output tokens produced
    public isolated function addOutputTokenCount(int count) {
        self.addTag(OUTPUT_TOKENS, count);
    }

    # Records the finish reason(s) returned by the model.
    #
    # + reason - A finish reason string or an array of reasons returned by the model
    public isolated function addFinishReason(string|string[] reason) {
        string[] reasons = reason is string[] ? reason : [reason];
        self.addTag(FINISH_REASON, reasons);
    }

    # Sets the response output type (e.g., text or json).
    #
    # + outputType - The output type describing the response format
    public isolated function addOutputType(OutputType outputType) {
        self.addTag(OUTPUT_TYPE, outputType);
    }

    # Records one or more stop sequences supplied to the model.
    #
    # + stopSequence - A single stop sequence or an array of stop sequences
    public isolated function addStopSequence(string|string[] stopSequence) {
        self.addTag(STOP_SEQUENCE, stopSequence);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    # Closes the span and records its final status.
    #
    # + err - Optional error that indicates if the operation failed
    public isolated function close(error? err = ()) {
        self.baseSpan.close(err);
    }
}

# Generate-content specific LLM span implementation.
public isolated distinct class GenerateContentSpan {
    *LlmSpan;
    private final BaseSpanImp baseSpan;

    isolated function init(string modelName) {
        self.baseSpan = new (string `${GENERATE_CONTENT} ${modelName}`);
        self.addTag(OPERATION_NAME, GENERATE_CONTENT);
        self.addTag(REQUEST_MODEL, modelName);
    }

    # Records the provider name used for the request.
    #
    # + providerName - The name of the AI provider/service (for example: `openai`)
    public isolated function addProvider(string providerName) {
        self.addTag(PROVIDER_NAME, providerName);
    }

    # Records the temperature setting used for the request.
    #
    # + temperature - The temperature value controlling randomness
    public isolated function addTemperature(float|decimal temperature) {
        self.addTag(TEMPERATURE, temperature);
    }

    # Records the input messages payload for the request.
    #
    # + messages - The input messages sent to the model
    public isolated function addInputMessages(json messages) {
        self.addTag(INPUT_MESSAGES, messages);
    }

    # Records the output messages payload produced by the model.
    #
    # + messages - The output messages returned by the model
    public isolated function addOutputMessages(json messages) {
        self.addTag(OUTPUT_MESSAGES, messages);
    }

    # Records the model name used for the response.
    #
    # + modelName - The model identifier/name used to generate the response (for example: `gpt-40-2024`)
    public isolated function addResponseModel(string modelName) {
        self.addTag(RESPONSE_MODEL, modelName);
    }

    # Records the tools schema send to the model.
    #
    # + tools - An array of tool schemas sent the the model
    public isolated function addTools(json[] tools) {
        self.addTag(INPUT_TOOLS, tools);
    }

    # Records the response identifier assigned by the provider.
    #
    # + id - The provider-assigned response identifier
    public isolated function addResponseId(string|int id) {
        self.addTag(RESPONSE_ID, id);
    }

    # Records the count of input tokens consumed by the request.
    #
    # + count - Number of input tokens consumed
    public isolated function addInputTokenCount(int count) {
        self.addTag(INPUT_TOKENS, count);
    }

    # Records the count of output tokens produced by the response.
    #
    # + count - Number of output tokens produced
    public isolated function addOutputTokenCount(int count) {
        self.addTag(OUTPUT_TOKENS, count);
    }

    # Records the finish reason(s) returned by the model.
    #
    # + reason - A finish reason string or an array of reasons returned by the model
    public isolated function addFinishReason(string|string[] reason) {
        string[] reasons = reason is string[] ? reason : [reason];
        self.addTag(FINISH_REASON, reasons);
    }

    # Sets the response output type (e.g., text or json).
    #
    # + outputType - The output type describing the response format
    public isolated function addOutputType(OutputType outputType) {
        self.addTag(OUTPUT_TYPE, outputType);
    }

    # Records one or more stop sequences supplied to the model.
    #
    # + stopSequence - A single stop sequence or an array of stop sequences
    public isolated function addStopSequence(string|string[] stopSequence) {
        self.addTag(STOP_SEQUENCE, stopSequence);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    # Closes the span and records its final status.
    #
    # + err - Optional error that indicates if the operation failed
    public isolated function close(error? err = ()) {
        self.baseSpan.close(err);
    }
}
