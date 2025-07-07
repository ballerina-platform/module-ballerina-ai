// Copyright (c) 2025 WSO2 LLC. (http://www.wso2.com).
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

import ballerina/io;
import ballerina/test;

isolated client class MockEmbeddingProvider {
    *EmbeddingProvider;

    isolated remote function embed(Chunk chunk) returns Embedding|Error {
        if chunk !is TextChunk {
            return error Error("Unable to generate embeding for the provided chunk");
        }
        do {
            string content = chunk.content;
            // read the prestored embding from json file
            json jsonEmedding = check io:fileReadJson(string `./tests/resources/embedding/${content}.json`);
            Embedding embedding = check jsonEmedding.cloneWithType();
            return embedding;
        } on fail error err {
            return error Error("Failed to generate embding for the provided chunk", err);
        }
    }
}

final MockEmbeddingProvider mockEmbeddingProvider = new;

@test:Config
isolated function testInMemoryVectorStore() returns error? {
    VectorStore vectorStore = check new InMemoryVectorStore(topK = 5);
    string[] words = [
        "puppy","car","automobile","happy","joyful","fast","quick","teacher","instructor","big",
        "large","city","town","purchase","buy","intelligent","smart","doctor","physician"
    ];

    VectorEntry[] vectorEntries = [];
    foreach string word in words {
        TextChunk chunk = {content: word};
        Embedding embedding = check mockEmbeddingProvider->embed(chunk);

        vectorEntries.push({chunk, embedding});
    }
    check vectorStore.add(vectorEntries);

    TextChunk dog = {content: "dog"};
    Embedding dogEmbedding = check mockEmbeddingProvider->embed(dog);
    VectorMatch[] vectorMatch = check vectorStore.query({embedding: dogEmbedding});
    test:assertEquals(vectorMatch[0].chunk.content, "puppy");
}
