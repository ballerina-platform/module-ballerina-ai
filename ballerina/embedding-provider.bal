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

# Represents an embedding provider that converts text documents into vector embeddings for similarity search.
public type EmbeddingProvider isolated client object {

    # Converts the given document into a vector embedding.
    #
    # + document - The document to convert into an embedding.
    # + return - The embedding vector representation on success, or an `Error` if the operation fails.
    isolated remote function embed(Document document) returns Embedding|Error;
};

# WSO2 embedding provider implementation that provides embedding capabilities using WSO2's AI service.
public isolated client class Wso2EmbeddingProvider {
    *EmbeddingProvider;
    private final intelligence:Client embeddingClient;

    # Initializes a new `Wso2EmbeddingProvider` instance.
    #
    # + config - The configuration containing the service URL and access token
    # + return - `nil` on success, or an `Error` if initialization fails
    public isolated function init(*Wso2ProviderConfig config) returns Error? {
        intelligence:Client|error embeddingClient = new (config = {auth: {token: config.accessToken}}, serviceUrl = config.serviceUrl);
        if embeddingClient is error {
            return error Error("Failed to initialize Wso2ModelProvider", embeddingClient);
        }
        self.embeddingClient = embeddingClient;
    }

    # Converts document to embedding.
    #
    # + document - The document to embed
    # + return - Embedding representation of document or an `Error` if the embedding service fails
    isolated remote function embed(Document document) returns Embedding|Error {
        intelligence:EmbeddingRequest request = {input: document.content};
        intelligence:EmbeddingResponse|error response = self.embeddingClient->/embeddings.post(request);
        if response is error {
            return error Error("Error generating embedding for provided document", response);
        }
        return response.data[0].embedding;
    }
}
