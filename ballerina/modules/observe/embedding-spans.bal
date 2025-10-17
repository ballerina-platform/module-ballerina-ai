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

# Represents a tracing span for embedding model operations.
public isolated distinct class EmbeddingSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    # Initializes a new embedding span for the given model name.
    #
    # + embeddingModelName - The name of the embedding model used
    isolated function init(string embeddingModelName) {
        self.baseSpan = new (string `${EMBEDDINGS} ${embeddingModelName}`);
        self.addTag(OPERATION_NAME, EMBEDDINGS);
        self.addTag(REQUEST_MODEL, embeddingModelName);
    }

    # Records the response model name used for the embedding.
    #
    # + model - The model identifier/name used to generate the embedding
    public isolated function addResponseModel(string model) {
        self.addTag(RESPONSE_MODEL, model);
    }

    # Records the provider name used for the embedding request.
    #
    # + providerName - The name of the AI provider/service (for example: `openai`)
    public isolated function addProvider(string providerName) {
        self.addTag(PROVIDER_NAME, providerName);
    }

    // Not mandated by spec
    # Records the input content for the embedding request.
    #
    # + content - The input content to be embedded
    public isolated function addInputContent(anydata content) {
        self.addTag(INPUT_CONTENT, content);
    }

    # Records the input token count for the embedding request.
    #
    # + count - Number of input tokens consumed
    public isolated function addInputTokenCount(int count) {
        self.addTag(INPUT_TOKENS, count);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    # Closes the embedding span and records its final status.
    #
    # + err - Optional error that indicates if the operation failed
    public isolated function close(error? err = ()) {
        self.baseSpan.close(err);
    }
}
