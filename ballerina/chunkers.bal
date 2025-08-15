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

import ballerina/jballerina.java;

# Represents a chunker that can process documents and return chunks.
public type Chunker isolated object {
    # Chunks the provided document.
    # + document - The input document to be chunked
    # + return - An array of chunks, or an `ai:Error` if the chunking fails
    public isolated function chunk(Document document) returns Chunk[]|Error;
};

# Represents a Genereric document chunker.
# Provides functionality to recursively chunk a text document using a configurable strategy.
#
# The chunking process begins with the specified strategy and recursively falls back to
# finer-grained strategies if the content exceeds the configured `maxChunkSize`. Overlapping content
# between chunks can be controlled using `maxOverlapSize`.
public isolated class GenericRecursiveChunker {
    *Chunker;
    private final int maxChunkSize;
    private final int maxOverlapSize;
    private final RecursiveChunkStrategy strategy;

    # Initializes a new instance of the `GenericRecursiveChunker`.
    #
    # + maxChunkSize - Maximum number of characters allowed per chunk
    # + maxOverlapSize - Maximum number of characters to reuse from the end of the previous chunk when creating the next one.
    # This overlap is made of complete sentences taken in reverse from the previous chunk, without exceeding
    # this limit. It helps maintain context between chunks during splitting.
    # + strategy - The recursive chunking strategy to use. Defaults to `PARAGRAPH`
    public isolated function init(int maxChunkSize = 200, int maxOverlapSize = 40,
            RecursiveChunkStrategy strategy = PARAGRAPH) {
        self.maxChunkSize = maxChunkSize;
        self.maxOverlapSize = maxOverlapSize;
        self.strategy = strategy;
    }

    # Chunks the provided document.
    # + document - The input document to be chunked
    # + return - An array of chunks, or an `ai:Error` if the chunking fails
    public isolated function chunk(Document document) returns Chunk[]|Error {
        return chunkDocumentRecursively(document, self.maxChunkSize, self.maxOverlapSize, self.strategy);
    }
}

# Provides functionality to recursively chunk a text document using a configurable strategy.
#
# The chunking process begins with the specified strategy and recursively falls back to
# finer-grained strategies if the content exceeds the configured `maxChunkSize`. Overlapping content
# between chunks can be controlled using `maxOverlapSize`.
#
# + document - The input document or string to be chunked
# + maxChunkSize - Maximum number of characters allowed per chunk
# + maxOverlapSize - Maximum number of characters to reuse from the end of the previous chunk when creating the next one.
# This overlap is made of complete sentences taken in reverse from the previous chunk, without exceeding
# this limit. It helps maintain context between chunks during splitting.
# + strategy - The recursive chunking strategy to use. Defaults to `PARAGRAPH`
# + return - An array of chunks, or an `ai:Error` if the chunking fails.
public isolated function chunkDocumentRecursively(Document|string document, int maxChunkSize = 200, int maxOverlapSize = 40,
        RecursiveChunkStrategy strategy = PARAGRAPH) returns Chunk[]|Error {
    if document !is TextDocument|TextChunk && document !is string {
        return error Error("Only text documents are supported for chunking");
    }
    TextDocument|TextChunk textDocument = document is string ? <TextDocument>{content: document} : document;
    return chunkTextDocument(textDocument, maxChunkSize, maxOverlapSize, strategy);
}

isolated function chunkTextDocument(TextDocument|TextChunk document, int chunkSize, int overlapSize,
        RecursiveChunkStrategy chunkStrategy, typedesc<TextChunk> textChunkType = TextChunk)
        returns TextChunk[]|Error = @java:Method {
    'class: "io.ballerina.stdlib.ai.Chunkers"
} external;

public isolated function chunkMarkdownDocument(MarkdownDocument document, int chunkSize, int overlapSize,
        MarkdownChunkStrategy chunkStrategy) returns TextChunk[]|Error {
    return chunkMarkdownDocumentInner(document, chunkSize, overlapSize, chunkStrategy);
}

isolated function chunkMarkdownDocumentInner(MarkdownDocument document, int chunkSize, int overlapSize,
        MarkdownChunkStrategy chunkStrategy, typedesc<TextChunk> textChunkType = TextChunk) returns TextChunk[]|Error = @java:Method {
    'class: "io.ballerina.stdlib.ai.Chunkers",
    name: "chunkMarkdownDocument"
} external;

# Represents the available strategies for recursively chunking a document.
#
# Each strategy attempts to include as much content as possible using a specific unit (such as paragraph or sentence).
# If the content exceeds the defined `maxChunkSize` in `RecursiveChunker`, the strategy recursively falls back
# to a finer-grained unit until the content fits within the limit.
public enum RecursiveChunkStrategy {

    # Splits text by individual characters.
    CHARACTER,

    # Splits text by words. Falls back to CHARACTER if the chunk exceeds the size limit.
    #
    # Word boundaries are detected using at least one space character (" ").
    # Any extra whitespace before or after words, such as multiple spaces or newline characters, is ignored.
    # Examples of valid word separators include " ", "  ", "\n", and " \n ".
    # When multiple words fit within the limit, they are joined together using a single space (" ").
    WORD,

    # Splits text by lines. Falls back to WORD, then CHARACTER, if the chunk exceeds the size limit.
    #
    # Line boundaries are identified using at least one newline character ("\n").
    # Any extra whitespace before or after lines is ignored.
    # Examples of valid line separators include "\n", "\n\n", " \n", and "\n ".
    # When multiple lines fit within the limit, they are joined together using a single newline ("\n").
    LINE,

    # Splits text by sentences. Falls back to WORD, then CHARACTER, if the chunk exceeds the size limit.
    #
    # Sentence boundaries are detected using OpenNLP's sentence detector (https://opennlp.apache.org).
    # When multiple sentences fit within the limit, they are joined together using a single space (" ").
    SENTENCE,

    # Splits text by paragraphs. Falls back to SENTENCE, then WORD, then CHARACTER, if the chunk exceeds the size limit.
    #
    # Paragraph boundaries are detected using at least two newline characters ("\n\n").
    # Any extra whitespace before, between, or after paragraphs is ignored.
    # Examples of valid paragraph separators include "\n\n", "\n\n\n", "\n \n", and " \n \n ".
    # When multiple paragraphs fit within the limit, they are joined together using a double newline ("\n\n").
    PARAGRAPH
}

# Represents the available strategies for chunking markdown documents.
#
# Each strategy attempts to preserve markdown structural boundaries while keeping chunks within size limits.
# Strategies are hierarchical - if content exceeds limits, the chunker falls back to finer-grained strategies.
public enum MarkdownChunkStrategy {

    MARKDOWN_HEADER,

    CODE_BLOCK,

    HORIZONTAL_LINE,

    PARAGRAPH,

    LINE,

    SENTENCE,

    WORD,

    CHARACTER
}
