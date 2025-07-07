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

import ballerina/test;

final EmbeddingProvider embeddingModel = new MockEmbeddingProvider();
final VectorStore vectorStore = check new InMemoryVectorStore();
final KnowledgeBase knowledgeBase = new VectorKnowledgeBase(vectorStore, embeddingModel);

@test:Config
isolated function testKnowledgeBase() returns error? {
    Chunk[] chunks = words.'map(word => <TextChunk>{content: word});

    check knowledgeBase.index(chunks);

    QueryMatch[] queryMatch = check knowledgeBase.retrieve("dog");
    test:assertEquals(queryMatch[0].chunk.content, "puppy");
}

@test:Config
isolated function testaugmentUserQueryMethod() returns error? {
    QueryMatch[] queryMatch = check knowledgeBase.retrieve("dog");
    ChatUserMessage userMessage = augmentUserQuery(queryMatch, "What is similar to 'dog' ?");
    test:assertTrue(userMessage.content is PromptParts, "Expected the 'content' field to be of type 'PromptParts',"
            + " but found 'string' instead.");
}
