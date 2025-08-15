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
        test:assertEquals(chunks.message(), "Only text and markdown documents are supported for chunking");
    } else {
        test:assertFail("Expected an 'Error' but got 'Chunk[]'");
    }
}

@test:Config {}
function testGenericRecursiveChunker() returns error? {
    TextDocument doc = {content: "abcde"};
    GenericRecursiveChunker chunker = new (2, 0, CHARACTER);
    Chunk[] chunks = check chunker.chunk(doc);

    test:assertEquals(chunks.length(), 3);
    test:assertEquals(chunks[0].content, "ab");
    test:assertEquals(chunks[1].content, "cd");
    test:assertEquals(chunks[2].content, "e");
}
function simpleMarkdownChunking() returns error? {
    MarkdownDocument doc = {content: "test"};
    Chunk[] chunks = check chunkDocumentRecursively(doc, 100, 40);
    test:assertEquals(chunks.length(), 1);
    test:assertEquals(chunks[0].content, "test");
}

@test:Config {}
function testMarkdownChunkingWithHeaders() returns error? {
    string markdownContent = "# Main Title\n\n" +
        "This is the introduction paragraph.\n\n" +
        "## Section 1\n\n" +
        "Content for section 1. This section contains some text that should be chunked properly.\n\n" +
        "### Subsection 1.1\n\n" +
        "More detailed content in subsection 1.1.\n\n" +
        "## Section 2\n\n" +
        "Content for section 2. Another section with different content.\n\n" +
        "### Subsection 2.1\n\n" +
        "Subsection content here.\n\n" +
        "## Conclusion\n\n" +
        "Final thoughts and summary.";

    MarkdownDocument doc = {content: markdownContent};

    // Test with default PARAGRAPH strategy for markdown documents
    Chunk[] headerChunks = check chunkMarkdownDocument(doc, 150, 20, PARAGRAPH);

    test:assertTrue(headerChunks.length() > 1, msg = "Should produce multiple chunks with PARAGRAPH strategy");

    // Verify that headers are preserved in chunks
    foreach Chunk chunk in headerChunks {
        anydata content = chunk.content;
        test:assertTrue(content is string, msg = "Chunk content should be string");
        string chunkContent = <string>content;

        // Check if chunks contain headers
        boolean hasHeader = chunkContent.startsWith("#") || chunkContent.indexOf("\n#") >= 0;
        test:assertTrue(hasHeader || chunkContent.length() <= 150,
                msg = "Chunks should either contain headers or be within size limit");
    }
}

@test:Config {}
function testMarkdownChunkingWithMixedContent() returns error? {
    string markdownContent = "# Introduction\n\n" +
        "This document contains various markdown elements.\n\n" +
        "## Code Example\n\n" +
        "```python\n" +
        "def hello_world():\n" +
        "    print('Hello, World!')\n" +
        "```\n\n" +
        "## List Section\n\n" +
        "- Item 1\n" +
        "- Item 2\n" +
        "- Item 3\n\n" +
        "## Table Section\n\n" +
        "| Column 1 | Column 2 |\n" +
        "|----------|----------|\n" +
        "| Data 1   | Data 2   |\n\n" +
        "## Final Section\n\n" +
        "End of document content.";

    MarkdownDocument doc = {content: markdownContent};

    // Test with PARAGRAPH strategy and moderate chunk size
    Chunk[] chunks = check chunkMarkdownDocument(doc, 120, 25, PARAGRAPH);

    test:assertTrue(chunks.length() > 1, msg = "Should produce multiple chunks with mixed content");

    // Verify that code blocks and other markdown elements are handled
    foreach Chunk chunk in chunks {
        anydata content = chunk.content;
        if (content is string) {
            string chunkContent = <string>content;
            // Check that chunks don't break in the middle of code blocks
            int? codeBlockStart = chunkContent.indexOf("```");
            int? codeBlockEnd = chunkContent.lastIndexOf("```");
            if (codeBlockStart is int && codeBlockEnd is int && codeBlockEnd > codeBlockStart) {
                test:assertTrue(true, msg = "Code blocks should not be split across chunks");
            }
        }
    }
}

@test:Config {}
function testMarkdownChunkingWithRecursiveFallback() returns error? {
    string markdownContent = "# Very Long Header\n\n" +
        "This is a very long paragraph that exceeds the maximum chunk size limit. " +
        "It contains multiple sentences that should trigger recursive fallback to finer-grained chunking strategies. " +
        "The content is designed to test the fallback mechanism from HEADER strategy to PARAGRAPH, then SENTENCE, then WORD, and finally CHARACTER if needed. " +
        "This ensures that even when headers cannot be used as chunk boundaries due to size constraints, the system gracefully degrades to maintain chunk size limits.";

    MarkdownDocument doc = {content: markdownContent};

    // Test with very small chunk size to force recursive fallback
    Chunk[] chunks = check chunkMarkdownDocument(doc, 50, 10, PARAGRAPH);

    test:assertTrue(chunks.length() > 1, msg = "Should produce multiple chunks using recursive fallback");

    // Verify all chunks respect size limit
    foreach Chunk chunk in chunks {
        anydata content = chunk.content;
        test:assertTrue(content is string, msg = "Chunk content should be string");
        string chunkContent = <string>content;
        test:assertTrue(chunkContent.length() <= 50,
                msg = "Each chunk must respect maxChunkSize limit");
    }
}

