// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
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

import ballerina/http;
import ballerina/test;

const int MOCK_EMBED_PORT = 9097;
const MOCK_EMBED_URL = "http://localhost:9097";

final float[] & readonly MOCK_EMBEDDING = [0.1, 0.2, 0.3, 0.4, 0.5];

// Mock intelligence service for Wso2EmbeddingProvider tests.
// Returns one embedding entry per input string, or multiple for array inputs.
service on new http:Listener(MOCK_EMBED_PORT) {

    resource function post embeddings(@http:Payload json payload, @http:Header string Authorization)
    returns json|error {
        if Authorization != "Bearer test-token" {
            return error("invalid authorization token");
        }
        json input = check payload.input;
        if input is json[] {
            json[] data = from int i in 0 ..< input.length()
                select {'object: "embedding", index: i, embedding: MOCK_EMBEDDING};
            return {
                'object: "list",
                model: "text-embedding-3-small",
                data,
                usage: {prompt_tokens: input.length(), total_tokens: input.length()}
            };
        }
        return {
            'object: "list",
            model: "text-embedding-3-small",
            data: [{'object: "embedding", index: 0, embedding: MOCK_EMBEDDING}],
            usage: {prompt_tokens: 1, total_tokens: 1}
        };
    }
}

@test:Config {
    groups: ["wso2-embedding-provider"]
}
function testWso2EmbeddingProviderEmbedTextChunk() returns error? {
    Wso2EmbeddingProvider provider = check new (MOCK_EMBED_URL, "test-token");
    TextChunk chunk = {content: "Hello world"};
    Embedding embedding = check provider->embed(chunk);
    test:assertEquals(embedding, MOCK_EMBEDDING);
}

@test:Config {
    groups: ["wso2-embedding-provider"]
}
function testWso2EmbeddingProviderEmbedTextDocument() returns error? {
    Wso2EmbeddingProvider provider = check new (MOCK_EMBED_URL, "test-token");
    TextDocument doc = {content: "A document to embed"};
    Embedding embedding = check provider->embed(doc);
    test:assertEquals(embedding, MOCK_EMBEDDING);
}

@test:Config {
    groups: ["wso2-embedding-provider"]
}
function testWso2EmbeddingProviderBatchEmbed() returns error? {
    Wso2EmbeddingProvider provider = check new (MOCK_EMBED_URL, "test-token");
    TextChunk[] chunks = [
        {content: "First chunk"},
        {content: "Second chunk"},
        {content: "Third chunk"}
    ];
    Embedding[] embeddings = check provider->batchEmbed(chunks);
    test:assertEquals(embeddings.length(), 3);
    test:assertEquals(embeddings, [MOCK_EMBEDDING, MOCK_EMBEDDING, MOCK_EMBEDDING]);
}

@test:Config {
    groups: ["wso2-embedding-provider"]
}
function testWso2EmbeddingProviderEmbedUnsupportedChunkType() returns error? {
    Wso2EmbeddingProvider provider = check new (MOCK_EMBED_URL, "test-token");
    Chunk unsupportedChunk = {content: "test content", 'type: "unsupported"};
    Embedding|Error result = provider->embed(unsupportedChunk);
    if result !is Error {
        test:assertFail("Expected an Error for unsupported chunk type");
    }
    test:assertTrue(result.message().indexOf("Unsupported chunk type") !is (),
            string `Unexpected error message: "${result.message()}"`);
}
