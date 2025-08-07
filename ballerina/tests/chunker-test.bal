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

@test:Config {}
function testCharacterChunkingWithDocument() returns error? {
    TextDocument doc = {content: "abcde"};
    Chunk[] chunks = check chunkDocumentRecursively(doc, 2, 0, CHARACTER);

    test:assertEquals(chunks.length(), 3);
    test:assertEquals(chunks[0].content, "ab");
    test:assertEquals(chunks[1].content, "cd");
    test:assertEquals(chunks[2].content, "e");
}

@test:Config {}
function testCharacterChunkingWithString() returns error? {
    Chunk[] chunks = check chunkDocumentRecursively("abcde", 2, 0, CHARACTER);

    test:assertEquals(chunks.length(), 3);
    test:assertEquals(chunks[0].content, "ab");
    test:assertEquals(chunks[1].content, "cd");
    test:assertEquals(chunks[2].content, "e");
}

@test:Config {}
function testWordChunking() returns error? {
    TextDocument doc = {content: "hello world ballerina test"};
    Chunk[] chunks = check chunkDocumentRecursively(doc, 11, 0, WORD);

    test:assertEquals(chunks.length(), 3);
    test:assertEquals(chunks[0].content, "hello world");
    test:assertEquals(chunks[1].content, "ballerina");
    test:assertEquals(chunks[2].content, "test");
}

@test:Config {}
function testLineChunking() returns error? {
    TextDocument doc = {content: "line1\nline2\nline3\nline4"};
    Chunk[] chunks = check chunkDocumentRecursively(doc, 12, 0, LINE);

    test:assertEquals(chunks.length(), 2);
    test:assertEquals(chunks[0].content, "line1\nline2");
    test:assertEquals(chunks[1].content, "line3\nline4");
}

@test:Config {}
function testSentenceChunking() returns error? {
    TextDocument doc = {content: "This is sentence one. This is sentence two. This is three."};
    Chunk[] chunks = check chunkDocumentRecursively(doc, 40, 0, SENTENCE);

    test:assertEquals(chunks.length(), 2);
    test:assertEquals(chunks[0].content, "This is sentence one.");
    test:assertEquals(chunks[1].content, "This is sentence two. This is three.");
}

@test:Config {}
function testParagraphChunking() returns error? {
    TextDocument doc = {content: "Paragraph one.\n\nParagraph two is here.\n\nAnd three."};
    Chunk[] chunks = check chunkDocumentRecursively(doc, 40, 0, PARAGRAPH);

    test:assertEquals(chunks.length(), 2);
    test:assertEquals(chunks[0].content, "Paragraph one.\n\nParagraph two is here.");
    test:assertEquals(chunks[1].content, "And three.");
}

@test:Config {}
function testRecursiveChunking() returns error? {
    TextDocument doc = {
        content: "This is a very long paragraph that exceeds the maximum chunk size. "
                + "It contains multiple sentences. Here is another sentence."
    };
    int maxChunkSize = 50;
    Chunk[] chunks = check chunkDocumentRecursively(doc, maxChunkSize, 0);

    test:assertTrue(chunks.length() > 1, msg = "Should produce multiple chunks using recursive fallback");
    foreach Chunk chunk in chunks {
        anydata content = chunk.content;
        test:assertTrue(content is string && content.length() <= maxChunkSize, msg = "Each chunk must respect maxChunkSize");
    }
}

@test:Config {}
function testRecursiveChunkingWithOverlap() returns error? {
    TextDocument doc = {
        content: "Ballerina is a cloud-native programming language. It simplifies writing integrations. " +
        "Recursive chunking helps process long documents efficiently. " +
        "Overlapping chunks retain context across boundaries."
    };
    Chunk[] chunks = check chunkDocumentRecursively(doc, 100, 40);

    test:assertEquals(chunks.length(), 3);
    test:assertEquals(chunks[0].content,
            "Ballerina is a cloud-native programming language. It simplifies writing integrations.");
    test:assertEquals(chunks[1].content,
            "It simplifies writing integrations. Recursive chunking helps process long documents efficiently.");
    test:assertEquals(chunks[2].content, "Overlapping chunks retain context across boundaries.");
}

@test:Config {}
function testRecursiveChunkingWithUnsupportedDocumentType() returns error? {
    Document doc = {content: "test", 'type: "unknown"};
    Chunk[]|Error chunks = chunkDocumentRecursively(doc, 100, 40);
    if chunks is Error {
        test:assertEquals(chunks.message(), "Only text documents are supported for chunking");
    } else {
        test:assertFail("Expected an 'Error' but got 'Chunk[]'");
    }
}
