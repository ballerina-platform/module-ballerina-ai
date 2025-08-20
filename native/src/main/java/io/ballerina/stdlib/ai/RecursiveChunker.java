/*
 *  Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
 *
 *  WSO2 LLC. licenses this file to you under the Apache License,
 *  Version 2.0 (the "License"); you may not use this file except
 *  in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing,
 *  software distributed under the License is distributed on an
 *  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 *  KIND, either express or implied.  See the License for the
 *  specific language governing permissions and limitations
 *  under the License.
 */

package io.ballerina.stdlib.ai;

import dev.langchain4j.data.document.Metadata;
import dev.langchain4j.data.segment.TextSegment;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.atomic.AtomicLong;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

class RecursiveChunker {

    // Types that should not be merged with other chunks
    private final Set<String> nonMergeableTypes;

    RecursiveChunker(Set<String> nonMergeableTypes) {
        this.nonMergeableTypes = nonMergeableTypes;
    }

    List<Chunk> chunkUsingSplitters(String content, List<Splitter> splitters, int maxChunkSize, int maxOverlapSize) {
        return chunkUsingSplittersInner(content, splitters, maxChunkSize, maxOverlapSize, Collections.emptyMap());
    }

    private List<Chunk> chunkUsingSplittersInner(String content, List<Splitter> splitters,
                                                 int maxChunkSize, int maxOverlapSize,
                                                 Map<String, String> parentMetadata) {
        return this.mergeChunksWithOverlap(splitters,
                chunkWithNoMerge(content, splitters, maxChunkSize, parentMetadata), maxChunkSize,
                maxOverlapSize);
    }

    private List<Chunk> chunkWithNoMerge(String content, List<Splitter> delimiters,
                                         int maxChunkSize, Map<String, String> parentMetadata) {
        List<Chunk> chunks = new ArrayList<>();
        List<Splitter> rest = delimiters.subList(1, delimiters.size());
        Iterator<Chunk> pieces = delimiters.getFirst().split(content);
        while (pieces.hasNext()) {
            Chunk piece = pieces.next();
            if (isNonMergeable(piece)) {
                // Add non-mergeable piece directly
                if (piece.length() > maxChunkSize) {
                    chunks.addAll(breakUpChunk(piece, maxChunkSize));
                } else {
                    chunks.add(piece);
                }
                continue;
            }
            if (piece.length() <= maxChunkSize) {
                chunks.add(piece);
            } else {
                // Recursively split chunk
                chunks.addAll(chunkWithNoMerge(piece.piece, rest, maxChunkSize, piece.metadata));
            }

        }
        if (parentMetadata.isEmpty()) {
            return chunks;
        }
        return chunks.stream().map(chunk -> {
            HashMap<String, String> metadata = new HashMap<>(parentMetadata);
            metadata.putAll(chunk.metadata);
            return new Chunk(chunk.piece(), Collections.unmodifiableMap(metadata));
        }).toList();
    }

    private boolean isNonMergeable(Chunk chunk) {
        if (!chunk.metadata().containsKey("type")) {
            return false;
        }
        String type = chunk.metadata().get("type");
        return nonMergeableTypes.contains(type);
    }

    static List<Chunk> breakUpChunk(Chunk chunk, int maxChunkSize) {
        List<Chunk> chunks = new ArrayList<>();
        Chunk remainder = chunk;
        Chunk previousChunk = null;

        while (remainder.length() > maxChunkSize) {
            // Create metadata with link to previous chunk
            Map<String, String> chunkMetadata = new HashMap<>(remainder.metadata);
            if (previousChunk != null) {
                chunkMetadata.put("prev", String.valueOf(previousChunk.id()));
            }

            Chunk part = new Chunk(remainder.piece().substring(0, maxChunkSize), chunkMetadata);
            chunks.add(part);
            previousChunk = part;

            remainder = new Chunk(remainder.piece().substring(maxChunkSize, remainder.length()), remainder.metadata);
        }

        if (!remainder.isEmpty()) {
            // Add metadata with link to previous chunk for the remainder
            Map<String, String> remainderMetadata = new HashMap<>(remainder.metadata);
            if (previousChunk != null) {
                remainderMetadata.put("prev", String.valueOf(previousChunk.id()));
            }
            chunks.add(new Chunk(remainder.piece(), remainderMetadata));
        }

        return chunks;
    }

    private List<Chunk> mergeChunksWithOverlap(List<Splitter> splitters, List<Chunk> pieces, int maxChunkSize,
                                               int maxOverlapSize) {
        List<Chunk> chunks = new ArrayList<>();
        List<Chunk> mergeBuffer = new ArrayList<>();
        int mergeBufferSize = 0;
        for (Chunk piece : pieces) {
            // If this piece is non-mergeable, flush buffer and add it directly
            if (isNonMergeable(piece)) {
                assert piece.length() <= maxChunkSize;
                // First flush the merge buffer
                mergeBuffer.stream().reduce(Chunk::merge).ifPresent(chunks::add);
                mergeBuffer.clear();
                mergeBufferSize = 0;

                // Add non-mergeable piece directly
                chunks.add(piece);
                // if non-mergeable can't be used as an overlap, reset lastChunk
                continue;
            }

            if (piece.length() > maxChunkSize) {
                List<Chunk> p = breakUpChunk(piece, maxChunkSize);
                assert p.size() > 1;
                chunks.addAll(p.subList(0, p.size() - 2));
                piece = p.getLast();
            }
            if (mergeBuffer.isEmpty()) {
                // First chunk
                assert piece.length() <= maxChunkSize;
                mergeBuffer.add(piece);
                mergeBufferSize += piece.length();
            } else if (mergeBufferSize + piece.length() <= maxChunkSize) {
                // Add to the merge buffer
                mergeBuffer.add(piece);
                mergeBufferSize += piece.length();
            } else {
                // First flush the merge buffer
                mergeBuffer.stream().reduce(Chunk::merge).ifPresent(chunks::add);
                Chunk lastPiece;
                if (maxOverlapSize > 0) {
                    lastPiece = mergeBuffer.getLast();
                    if (lastPiece.length() > maxOverlapSize) {
                        List<Chunk> p = chunkWithNoMerge(lastPiece.piece(), splitters, maxOverlapSize,
                                lastPiece.metadata);
                        assert p.size() > 1;
                        lastPiece = p.getLast();
                    }
                } else {
                    lastPiece = Chunk.EMPTY;
                }
                mergeBuffer.clear();

                if (lastPiece.length() + piece.length() <= maxChunkSize) {
                    // Merge with the last piece
                    var pieceMetadata = piece.metadata;
                    piece = Chunk.merge(lastPiece, piece);
                    // Metadata should not be affected by overlap
                    piece = piece.appendMetadata(piece, pieceMetadata);
                }
                assert piece.length() <= maxChunkSize;
                mergeBuffer.add(piece);
                mergeBufferSize = piece.length();
            }
        }
        mergeBuffer.stream().reduce(Chunk::merge).ifPresent(chunks::add);
        return chunks;
    }

    @FunctionalInterface
    interface Splitter {

        Iterator<Chunk> split(String content);

        static Splitter createSentenceSplitter() {
            return new SimpleDelimiterSplitter("\\.");
        }

        static Splitter createWordSplitter() {
            return new SimpleDelimiterSplitter(" ");
        }

        static Splitter createCharacterSplitter() {
            return new SimpleDelimiterSplitter("");
        }
    }

    record Chunk(long id, String piece, Map<String, String> metadata) {

        Chunk {
            assert piece != null;
            assert metadata != null;
        }

        private static final AtomicLong nextId = new AtomicLong(0);

        Chunk(String piece, Map<String, String> metadata) {
            this(nextId.getAndIncrement(), piece, metadata);
        }

        public static final Chunk EMPTY = new Chunk("", Collections.emptyMap());

        public int length() {
            return piece.length();
        }

        public boolean isEmpty() {
            return piece.isEmpty();
        }

        public static Chunk merge(Chunk first, Chunk second) {
            String mergedPiece = first.piece + second.piece;
            Map<String, String> mergedMetadata = new HashMap<>();
            for (String key : first.metadata().keySet()) {
                if (second.metadata.containsKey(key) && second.metadata.get(key).equals(first.metadata.get(key))) {
                    mergedMetadata.put(key, first.metadata.get(key));
                }
            }
            return new Chunk(mergedPiece, Collections.unmodifiableMap(mergedMetadata));
        }

        public TextSegment toTextSegment(int index) {
            Map<String, Object> metadata = new HashMap<>(this.metadata);
            metadata.put("id", id);
            metadata.put("index", index);
            return new TextSegment(piece, new Metadata(metadata));
        }

        public Chunk appendMetadata(Chunk base, Map<String, String> metadata) {
            Map<String, String> newMetadata = new HashMap<>(base.metadata);
            newMetadata.putAll(metadata);
            return new Chunk(base.piece, Collections.unmodifiableMap(newMetadata));
        }
    }

    static class SimpleDelimiterSplitter implements Splitter {

        private final Pattern pattern;

        SimpleDelimiterSplitter(String delimiter) {
            pattern = Pattern.compile(Pattern.quote(delimiter));
        }

        @Override
        public Iterator<Chunk> split(String content) {
            return new Iterator<>() {
                private final Matcher matcher = pattern.matcher(content);
                private int lastIndex = 0;
                private String nextPiece = null;
                private boolean hasNextPiece = false;
                private boolean finished = false;

                private void prepareNext() {
                    if (finished) {
                        return;
                    }

                    if (matcher.find()) {
                        int delimiterStart = matcher.start();
                        int delimiterEnd = matcher.end();

                        if (delimiterStart > lastIndex) {
                            // Next piece is the content before the delimiter
                            nextPiece = content.substring(lastIndex, delimiterStart);
                            lastIndex = delimiterStart;
                            hasNextPiece = true;
                            return;
                        }

                        // Next piece is the delimiter itself
                        nextPiece = content.substring(delimiterStart, delimiterEnd);
                        lastIndex = delimiterEnd;
                        hasNextPiece = true;
                        return;
                    }

                    if (lastIndex < content.length()) {
                        // Remaining content after last delimiter
                        nextPiece = content.substring(lastIndex);
                        lastIndex = content.length();
                        hasNextPiece = true;
                    } else {
                        hasNextPiece = false;
                    }
                    finished = true;
                }

                @Override
                public boolean hasNext() {
                    if (!hasNextPiece && !finished) {
                        prepareNext();
                    }
                    return hasNextPiece;
                }

                @Override
                public Chunk next() {
                    if (!hasNext()) {
                        throw new java.util.NoSuchElementException();
                    }
                    hasNextPiece = false;

                    return new Chunk(nextPiece, Map.of());
                }
            };
        }
    }
}
