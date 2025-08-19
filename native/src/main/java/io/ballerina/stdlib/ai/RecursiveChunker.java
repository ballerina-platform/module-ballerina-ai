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
import java.util.function.Predicate;
import java.util.stream.Stream;

class RecursiveChunker {

    // Types that should not be merged with other chunks
    private final Set<String> nonMergeableTypes;

    RecursiveChunker(Set<String> nonMergeableTypes) {
        this.nonMergeableTypes = nonMergeableTypes;
    }

    List<Chunk> chunkUsingSplitters(String content, List<Splitter> delimiters, int maxChunkSize, int maxOverlapSize) {
        return chunkUsingSplittersInner(content, delimiters, maxChunkSize, maxOverlapSize, Collections.emptyMap());
    }

    static final class Context {

        private final List<Chunk> chunks;
        private final List<Chunk> nextChunkPieceBuffer;
        private int nextChunkSize;

        Context() {
            chunks = new ArrayList<>();
            nextChunkPieceBuffer = new ArrayList<>();
            nextChunkSize = 0;
        }

        void flushBuffer() {
            nextChunkPieceBuffer.stream().reduce(Chunk::merge).ifPresent(chunks::add);
            nextChunkPieceBuffer.clear();
            nextChunkSize = 0;
        }

        void addChunk(Chunk chunk) {
            chunks.add(chunk);
        }

        void addChunks(List<Chunk> newChunks) {
            chunks.addAll(newChunks);
        }

        public int nextChunkSize() {
            return nextChunkSize;
        }

        public void addPiece(Chunk piece) {
            nextChunkPieceBuffer.add(piece);
            nextChunkSize += piece.length();
        }

        public Stream<Chunk> chunks(ChunkMergeStrategy mergeStrategy, int maxChunkSize, int maxOverlapSize) {
            return mergeStrategy.merge(chunks, maxChunkSize, maxOverlapSize).stream()
                    .filter(Predicate.not(Chunk::isEmpty));
        }
    }

    @FunctionalInterface
    interface ChunkMergeStrategy {

        List<Chunk> merge(List<Chunk> chunks, int maxChunkSize, int maxOverlapSize);
    }

    private List<Chunk> chunkUsingSplittersInner(String content, List<Splitter> delimiters,
                                                 int maxChunkSize, int maxOverlapSize,
                                                 Map<String, String> parentMetadata) {
        Context cx = new Context();
        List<Splitter> rest = delimiters.subList(1, delimiters.size());
        Iterator<Chunk> pieces = delimiters.getFirst().split(content);
        while (pieces.hasNext()) {
            Chunk piece = pieces.next();

            // If this piece is non-mergeable, flush buffer and add it directly
            if (isNonMergeable(piece)) {
                // Flush current buffer
                cx.flushBuffer();

                // Add non-mergeable piece directly
                if (piece.length() > maxChunkSize) {
                    cx.addChunks(breakUpChunk(piece, maxChunkSize));
                } else {
                    cx.addChunk(piece);
                }
                continue;
            }

            if (cx.nextChunkSize() + piece.length() <= maxChunkSize) {
                cx.addPiece(piece);
                continue;
            }

            cx.flushBuffer();

            // If the piece is smaller than the max chunk size, just add it to the next chunk
            if (piece.length() <= maxChunkSize) {
                cx.addPiece(piece);
                continue;
            }

            // Break up the current piece
            List<Chunk> pieceChunks =
                    chunkUsingSplittersInner(piece.piece, rest, maxChunkSize, maxOverlapSize, piece.metadata);
            cx.addChunks(pieceChunks.subList(0, pieceChunks.size() - 1));
            Chunk lastPieceChunk = pieceChunks.getLast();
            if (isNonMergeable(lastPieceChunk)) {
                // If the last piece is non-mergeable, add it directly
                cx.addChunk(lastPieceChunk);
            } else {
                cx.addPiece(lastPieceChunk);
            }
        }
        cx.flushBuffer();
        Stream<Chunk> chunks = cx.chunks(this::mergeChunksWithOverlap, maxChunkSize, maxOverlapSize);
        if (parentMetadata.isEmpty()) {
            return chunks.toList();
        }
        return chunks.map(chunk -> {
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

    private List<Chunk> mergeChunksWithOverlap(List<Chunk> pieces, int maxChunkSize, int maxOverlapSize) {
        List<Chunk> chunks = new ArrayList<>();
        List<Chunk> mergeBuffer = new ArrayList<>();
        int mergeBufferSize = 0;
        Chunk lastChunk = Chunk.EMPTY;
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
                continue;
            }

            if (piece.length() > maxChunkSize) {
                List<Chunk> p = breakUpChunk(piece, maxChunkSize);
                assert p.size() > 1;
                chunks.addAll(p.subList(0, p.size() - 2));
                piece = p.getLast();
            }
            if (mergeBuffer.isEmpty()) {
                // First chunk, see if we can overlap with the last piece
                if (lastChunk.length() < maxOverlapSize && lastChunk.length() + piece.length() <= maxChunkSize) {
                    // Merge with the last chunk
                    piece = Chunk.merge(lastChunk, piece);
                }
                mergeBuffer.add(piece);
                mergeBufferSize += piece.length();
            } else if (mergeBufferSize + piece.length() <= maxChunkSize) {
                // Add to the merge buffer
                mergeBuffer.add(piece);
                mergeBufferSize += piece.length();
            } else {
                // First flush the merge buffer
                mergeBuffer.stream().reduce(Chunk::merge).ifPresent(chunks::add);
                mergeBuffer.clear();

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
    }

    record Chunk(long id, String piece, Map<String, String> metadata) {

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
    }
}
