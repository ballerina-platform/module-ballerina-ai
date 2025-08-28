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

@test:Config
isolated function testVectorKnowledgeBase() returns error? {
    VectorKnowledgeBase kb = new (check new InMemoryVectorStore(), new MockEmbeddingProvider());
    from string word in words
    do {
        TextChunk chunk = {content: word, metadata: {fileName: "words.txt"}};
        check kb.ingest(chunk);
    };

    QueryMatch[] 'match = check kb.retrieve("dog", topK = 1);
    test:assertEquals('match.length(), 1);
    test:assertEquals('match[0].chunk.content, "puppy");

    MetadataFilters deleteFilter = {filters: [{'key: "fileName", value: "words.txt"}]};
    check kb.deleteByFilter(deleteFilter);
    'match = check kb.retrieve("dog");
    test:assertEquals('match.length(), 0);
}
