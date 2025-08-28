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

    isolated remote function batchEmbed(Chunk[] chunks) returns Embedding[]|Error {
        Embedding[] embeddings = [];
        foreach Chunk chunk in chunks {
            Embedding|Error embedding = check self->embed(chunk);
            if embedding is Error {
                return error Error("Failed to generate embeddings for the provided chunks", embedding);
            }
            embeddings.push(embedding);
        }
        return embeddings;
    }
}

final MockEmbeddingProvider mockEmbeddingProvider = new;
final readonly & string[] words = [
    "puppy","car","automobile","happy","joyful","fast","quick","teacher","instructor",
    "big","large","city","town","purchase","buy","intelligent","smart","doctor","physician"
];

@test:Config
isolated function testInMemoryStoreWithMetrics() returns error? {
    VectorStore vectorStore1 = check new InMemoryVectorStore(topK = 5);
    VectorStore vectorStore2 = check new InMemoryVectorStore(topK = 5, similarityMetric = DOT_PRODUCT);
    VectorStore vectorStore3 = check new InMemoryVectorStore(topK = 5, similarityMetric = EUCLIDEAN);

    VectorEntry[] vectorEntries = [];
    foreach string word in words {
        TextChunk chunk = {content: word};
        Embedding embedding = check mockEmbeddingProvider->embed(chunk);
        vectorEntries.push({chunk, embedding});
    }
    check vectorStore1.add(vectorEntries);
    check vectorStore2.add(vectorEntries);
    check vectorStore3.add(vectorEntries);

    TextChunk dog = {content: "dog"};
    Embedding dogEmbedding = check mockEmbeddingProvider->embed(dog);

    string expectedContent = "puppy";
    VectorMatch[] matchWithCosine = check vectorStore1.query({embedding: dogEmbedding});
    test:assertEquals(matchWithCosine[0].chunk.content, expectedContent);

    VectorMatch[] matchWithDotProduct = check vectorStore2.query({embedding: dogEmbedding});
    test:assertEquals(matchWithDotProduct[0].chunk.content, expectedContent);

    VectorMatch[] matchWithEuclidean = check vectorStore2.query({embedding: dogEmbedding});
    test:assertEquals(matchWithEuclidean[0].chunk.content, expectedContent);
}

@test:Config {}
isolated function testInMemoryStoreWithFilters() returns error? {
    VectorStore vectorStore1 = check new InMemoryVectorStore(topK = 5);
    VectorEntry[] vectorEntries = [];
    foreach string word in words {
        TextChunk chunk = {content: word, metadata: {
            fileName: "test.txt"
        }};
        Embedding embedding = check mockEmbeddingProvider->embed(chunk);
        vectorEntries.push({chunk, embedding});
    }
    check vectorStore1.add(vectorEntries);
    string expectedContent = "puppy";
    VectorMatch[] matchWithCosine = check vectorStore1.query({filters: {
        filters: [
            {
                'key: "fileName",
                operator: EQUAL,
                value: "test.txt"
            }
        ]}});
    test:assertEquals(matchWithCosine[0].chunk.content, expectedContent);

    matchWithCosine = check vectorStore1.query({filters: {
        filters: [
            {
                'key: "fileName",
                operator: EQUAL,
                value: "invalid_file_name.txt"
            }
        ]}});
    test:assertEquals(matchWithCosine.length(), 0);
}

@test:Config
isolated function testInMemoryVectorStoreWithInvalidTopKConfig() {
    VectorStore|Error vectorStore = new InMemoryVectorStore(topK = 0);
    if vectorStore is Error {
        test:assertEquals(vectorStore.message(), "topK must be greater than 0");
    } else {
        test:assertFail("Expected an 'Error' but got 'VectorStore'");
    }
}

@test:Config
isolated function testInMemoryVectorStoreWithSparseVector() returns error? {
    VectorStore vectorStore = check new InMemoryVectorStore(topK = 5);
    SparseVector vector = {indices: [], values: []};
    VectorEntry entry = {embedding: vector, chunk: {'type: "text", content: "test"}};
    Error? result = vectorStore.add([entry]);
    if result is Error {
        test:assertEquals(result.message(), "InMemoryVectorStore supports dense vectors exclusively");
    } else {
        test:assertFail("Expected an 'Error' but got '()'");
    }
}

@test:Config
isolated function testInMemoryVectorDeletion() returns error? {
    VectorStore vectorStore = check new InMemoryVectorStore(topK = 5);
    int id = 0;

    VectorEntry[] vectorEntries = [];
    foreach string word in words {
        TextChunk chunk = {content: word};
        Embedding embedding = check mockEmbeddingProvider->embed(chunk);
        vectorEntries.push({chunk, embedding, id: id.toString()});
        id += 1;
    }

    check vectorStore.add(vectorEntries);

    foreach int i in 0 ..< vectorEntries.length() {
        check vectorStore.delete(i.toString());
    }

    int invalidId = vectorEntries.length();
    Error? result = vectorStore.delete(invalidId.toString());
    if result is Error {
        test:assertEquals(result.message(), string `Vector entry with reference id '${invalidId}' not found`);
    } else {
        test:assertFail("Expected an 'Error' but got '()'");
    }
}
