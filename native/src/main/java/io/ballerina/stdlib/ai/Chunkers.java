/*
 * Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.stdlib.ai;

import dev.langchain4j.data.document.Document;
import dev.langchain4j.data.document.DocumentSplitter;
import dev.langchain4j.data.document.Metadata;
import dev.langchain4j.data.document.splitter.DocumentByCharacterSplitter;
import dev.langchain4j.data.document.splitter.DocumentByLineSplitter;
import dev.langchain4j.data.document.splitter.DocumentByParagraphSplitter;
import dev.langchain4j.data.document.splitter.DocumentBySentenceSplitter;
import dev.langchain4j.data.document.splitter.DocumentByWordSplitter;
import dev.langchain4j.data.segment.TextSegment;
import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BTypedesc;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Native utility class for chunking text documents into smaller segments using various strategies.
 * Supports splitting by line, character, word, sentence, or paragraph.
 */
public class Chunkers {
    private static final String TEXT_CHUNK_RECORD_TYPE_NAME = "TextChunk";
    private static final String META_DATA_RECORD_TYPE_NAME = "Metadata";
    private static final String CONTENT_FIELD_NAME = "content";
    private static final String METADATA_FIELD_NAME = "metadata";
    private static final String INDEX_FIELD_NAME = "index";

    public static Object chunkTextDocument(BMap<BString, Object> document, int chunkSize, int maxOverlapSize,
                                           BString chunkStrategy, BTypedesc textChunkType) {
        try {
            String content = document.getStringValue(StringUtils.fromString(CONTENT_FIELD_NAME)).getValue();
            Document inputDocument = Document.from(content);

            DocumentSplitter splitter = getDocumentSplitter(chunkStrategy, chunkSize, maxOverlapSize);
            List<TextSegment> textSegments = splitter.split(inputDocument);

            return createTextChunkRecordArray(document, textSegments, textChunkType.getDescribingType());
        } catch (RuntimeException e) {
            return handleChunkingErrors(e);
        }
    }

    public static Object chunkMarkdownDocument(BMap<BString, Object> document, int chunkSize, int maxOverlapSize,
                                              BString chunkStrategy, BTypedesc textChunkType) {
        try {
            String content = document.getStringValue(StringUtils.fromString(CONTENT_FIELD_NAME)).getValue();
            MarkdownChunker.MarkdownChunkStrategy strategy = switch (chunkStrategy.getValue()) {
                case "MARKDOWN_HEADER" -> MarkdownChunker.MarkdownChunkStrategy.BY_HEADER;
                case "CODE_BLOCK" -> MarkdownChunker.MarkdownChunkStrategy.BY_CODE_BLOCK;
                case "HORIZONTAL_LINE" -> MarkdownChunker.MarkdownChunkStrategy.BY_HORIZONTAL_LINE;
                case "PARAGRAPH" -> MarkdownChunker.MarkdownChunkStrategy.BY_PARAGRAPH;
                case "LINE" -> MarkdownChunker.MarkdownChunkStrategy.BY_LINE;
                case "SENTENCE" -> MarkdownChunker.MarkdownChunkStrategy.BY_SENTENCE;
                case "WORD" -> MarkdownChunker.MarkdownChunkStrategy.BY_WORD;
                case "CHARACTER" -> MarkdownChunker.MarkdownChunkStrategy.BY_CHARACTER;
                default -> throw new IllegalArgumentException("unknown chunking strategy " + chunkStrategy.getValue());
            };
            List<TextSegment> textSegments = MarkdownChunker.chunk(content, strategy, chunkSize, maxOverlapSize);
            return createTextChunkRecordArray(document, textSegments, textChunkType.getDescribingType());
        } catch (RuntimeException e) {
            return handleChunkingErrors(e);
        }
    }

    private static DocumentSplitter getDocumentSplitter(BString chunkStrategy, int maxChunkSize, int overlapSize) {
        return switch (ChunkStrategy.fromString(chunkStrategy.getValue())) {
            case LINE -> new DocumentByLineSplitter(maxChunkSize, overlapSize);
            case CHARACTER -> new DocumentByCharacterSplitter(maxChunkSize, overlapSize);
            case WORD -> new DocumentByWordSplitter(maxChunkSize, overlapSize);
            case SENTENCE -> new DocumentBySentenceSplitter(maxChunkSize, overlapSize);
            case PARAGRAPH -> new DocumentByParagraphSplitter(maxChunkSize, overlapSize);
        };
    }

    private static BArray createTextChunkRecordArray(BMap<BString, Object> document, List<TextSegment> textSegments,
                                                     Type textChunkType) {
        Object[] chunkArray = textSegments.stream()
                .map(textSegment -> createTextChunkRecord(document, textSegment)).toArray();
        return ValueCreator.createArrayValue(chunkArray, TypeCreator.createArrayType(textChunkType));
    }

    private static BMap<BString, Object> createTextChunkRecord(BMap<BString, Object> document,
                                                               TextSegment textSegment) {
        Map<String, Object> textChunkRecordFields = new HashMap<>();
        textChunkRecordFields.put(CONTENT_FIELD_NAME, textSegment.text());
        textChunkRecordFields.put(METADATA_FIELD_NAME, createMetadataRecord(document, textSegment.metadata()));
        return ValueCreator.createRecordValue(ModuleUtils.getModule(), TEXT_CHUNK_RECORD_TYPE_NAME,
                textChunkRecordFields);
    }

    private static BMap<BString, Object> createMetadataRecord(BMap<BString, Object> document, Metadata metadata) {
        BMap<BString, Object> existingMetadata = document.containsKey(StringUtils.fromString(METADATA_FIELD_NAME))
                ? (BMap<BString, Object>) document.get(StringUtils.fromString(METADATA_FIELD_NAME))
                : ValueCreator.createMapValue();

        for (Map.Entry<String, Object> entry : metadata.toMap().entrySet()) {
            BString key = StringUtils.fromString(entry.getKey());
            Object value = entry.getValue();
            if (INDEX_FIELD_NAME.equals(entry.getKey()) && value instanceof String stringValue) {
                existingMetadata.put(key, Integer.parseInt(stringValue));
            } else if (value instanceof String strVal) {
                existingMetadata.put(key, StringUtils.fromString(strVal));
            } else if (!(value instanceof UUID)) {
                existingMetadata.put(key, value);
            }
        }

        return existingMetadata.isEmpty() ? null :
                ValueCreator.createRecordValue(ModuleUtils.getModule(), META_DATA_RECORD_TYPE_NAME, existingMetadata);
    }

    private static BError handleChunkingErrors(RuntimeException e) {
        // Since the concept of subSplitter is not exposed at the Ballerina level,
        // we modify the error message thrown by the underlying Java implementation.
        String subSplitterErrorRegex = ", and there is no subSplitter defined to split it further\\.";
        String errorMessage = e.getMessage().replaceAll(subSplitterErrorRegex, "");
        return ModuleUtils.createError(errorMessage);
    }
}

enum ChunkStrategy {
    LINE("LINE"),
    CHARACTER("CHARACTER"),
    WORD("WORD"),
    SENTENCE("SENTENCE"),
    PARAGRAPH("PARAGRAPH");

    private final String value;

    ChunkStrategy(String value) {
        this.value = value;
    }

    public static ChunkStrategy fromString(String value) {
        for (ChunkStrategy status : ChunkStrategy.values()) {
            if (status.value.equals(value)) {
                return status;
            }
        }
        throw new IllegalArgumentException("unknown chunking strategy " + value);
    }
}
