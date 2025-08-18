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

# Represents an embedding provider that converts chunk into vector embeddings for similarity search.
public type EmbeddingProvider distinct isolated client object {

    # Converts the given chunk into a vector embedding.
    #
    # + chunk - The chunk to be convert into an embedding
    # + return - The embedding vector representation on success, or an `ai:Error` if the operation fails
    isolated remote function embed(Chunk chunk) returns Embedding|Error;

    # Converts a batch of chunks into vector embeddings.
    #
    # + chunks - The array of chunks to be converted into embeddings
    # + return - An array of embeddings on success, or an `ai:Error` if the operation fails
    isolated remote function batchEmbed(Chunk[] chunks) returns Embedding[]|Error;
};

# WSO2 embedding provider implementation that provides embedding capabilities using WSO2's AI service.
public distinct isolated client class Wso2EmbeddingProvider {
    *EmbeddingProvider;
    private final intelligence:Client embeddingClient;

    # Initializes a new `Wso2EmbeddingProvider` instance.
    #
    # + serviceUrl - The base URL of WSO2 intelligence API endpoint
    # + accessToken - The access token for authenticating API requests
    # + connectionConfig - Additional HTTP connection configuration
    # + return - `nil` on success, or an `ai:Error` if initialization fails
    public isolated function init(string serviceUrl, string accessToken, *ConnectionConfig connectionConfig) returns Error? {
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
        intelligence:Client|error embeddingClient = new (intelligenceConfig, serviceUrl);
        if embeddingClient is error {
            return error Error("Failed to initialize Wso2ModelProvider", embeddingClient);
        }
        self.embeddingClient = embeddingClient;
    }

    # Converts chunk to embedding.
    #
    # + chunk - The data to embed
    # + return - Embedding representation of the chunk content or an `ai:Error` if the embedding service fails
    isolated remote function embed(Chunk chunk) returns Embedding|Error {
        if chunk !is TextChunk|TextDocument {
            return error Error("Unsupported chunk type. only 'ai:TextChunk|ai:TextDocument' is supported");
        }
        intelligence:EmbeddingRequest request = {input: chunk.content};
        intelligence:EmbeddingResponse|error response = self.embeddingClient->/embeddings.post(request);
        if response is error {
            return error Error("Error generating embedding for provided chunk", response);
        }
        intelligence:EmbeddingResponse_data[] responseData = response.data;
        if responseData.length() == 0 {
            return error Error("No embeddings generated for the provided chunk");
        }
        return responseData[0].embedding;
    }

    # Converts a batch of chunks into embeddings.
    #
    # + chunks - The array of chunks to be converted into embeddings
    # + return - An array of embeddings on success, or an `ai:Error`
    isolated remote function batchEmbed(Chunk[] chunks) returns Embedding[]|Error {
        if !isAllTextChunks(chunks) {
            return error Error("Unsupported chunk type. Expected elements of type 'ai:TextChunk|ai:TextDocument'.");
        }
        intelligence:EmbeddingRequest request = {input: chunks.map(chunk => chunk.content.toString())};
        intelligence:EmbeddingResponse|error response = self.embeddingClient->/embeddings.post(request);
        if response is error {
            return error Error("Error generating embedding for provided chunk", response);
        }
        intelligence:EmbeddingResponse_data[] responseData = response.data;
        if responseData.length() == 0 {
            return error Error("No embeddings generated for the provided chunk");
        }
        return responseData.map(data => data.embedding);
    }
}

isolated function isAllTextChunks(Chunk[] chunks) returns boolean {
    return chunks.every(chunk => chunk is TextChunk|TextDocument);
}
