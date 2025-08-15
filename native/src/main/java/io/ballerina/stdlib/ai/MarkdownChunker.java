package io.ballerina.stdlib.ai;

import dev.langchain4j.data.document.Document;
import dev.langchain4j.data.document.Metadata;
import dev.langchain4j.data.segment.TextSegment;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.function.Predicate;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

class MarkdownChunker {

    static Object chunkMarkdownDocumentInner(Document document, int chunkSize, int maxOverlapSize,
                                             ChunkStrategy strategy) {
        assert chunkSize > 0 : "chunkSize should be greater than 0";
        assert maxOverlapSize >= 0 : "maxOverlapSize should be greater than or equal to 0";
        assert chunkSize > maxOverlapSize;
        return null;
    }

    static List<TextSegment> chunk(String content, int chunkSize, int maxOverlapSize) {
        return chunkUsingDelimiters(content, List.of(
                new HeaderSplitter(2),
                new HeaderSplitter(3),
                new HeaderSplitter(4),
                new HeaderSplitter(5),
                new HeaderSplitter(6),
                new SimpleDelimiterSplitter("```\n"), // End of code block
                // Horizontal lines
                new SimpleDelimiterSplitter("\n\\*\\*\\*+\n"),
                new SimpleDelimiterSplitter("\\n---+\\n"),
                new SimpleDelimiterSplitter("\n___+\n"),
                new SimpleDelimiterSplitter("\n\n"),
                new SimpleDelimiterSplitter("\n"),
                new SimpleDelimiterSplitter(" "),
                new SimpleDelimiterSplitter("")), chunkSize, maxOverlapSize).stream()
                .map(chunk -> new TextSegment(chunk.piece, new Metadata(chunk.metadata))).toList();
    }

    private static List<Chunk> chunkUsingDelimiters(String content, List<Splitter> delimiters, int maxChunkSize,
                                                    int maxOverlapSize) {
        return chunkUsingDelimitersInner(content, delimiters, maxChunkSize, maxOverlapSize, Integer.MAX_VALUE,
                Collections.emptyMap());
    }

    private static List<Chunk> chunkUsingDelimitersInner(String content, List<Splitter> delimiters, int maxChunkSize,
                                                         int maxOverlapSize, int maxChunkCount,
                                                         Map<String, String> parentMetadata) {
        List<Splitter> rest = delimiters.subList(1, delimiters.size());
        Iterator<Chunk> pieces = delimiters.getFirst().split(content);
        List<Chunk> chunks = new ArrayList<>();
        List<Chunk> nextChunkPieceBuffer = new ArrayList<>();
        int nextChunkSize = 0;
        while (pieces.hasNext()) {
            Chunk piece = pieces.next();
            if (nextChunkSize + piece.length() <= maxChunkSize) {
                nextChunkPieceBuffer.add(piece);
                nextChunkSize += piece.length();
                continue;
            }

            nextChunkPieceBuffer.stream().reduce(Chunk::merge).ifPresent(chunks::add);
            nextChunkPieceBuffer.clear();
            nextChunkSize = 0;

//            // get the overlap part
//            if (maxOverlapSize != 0) {
//                if (lastPiece.length() < maxOverlapSize) {
//                    piece = Chunk.merge(lastPiece, piece);
//                } else {
//                    // Break the last piece to small chunks
//                    var lastPieceChunks = chunkUsingDelimitersInner(lastPiece.piece, rest, maxOverlapSize, 0, 1,
//                            lastPiece.metadata);
//                    piece = Chunk.merge(lastPieceChunks.getLast(), piece);
//                }
//            }

            // If the piece is smaller than the max chunk size, just add it to the next chunk
            if (piece.length() <= maxChunkSize) {
                nextChunkPieceBuffer.add(piece);
                nextChunkSize += piece.length();
                continue;
            }

            // Break up the current piece
            List<Chunk> pieceChunks = chunkUsingDelimitersInner(piece.piece, rest, maxChunkSize, maxOverlapSize,
                    Integer.MAX_VALUE, piece.metadata);
            chunks.addAll(pieceChunks.subList(0, pieceChunks.size() - 1));
            Chunk lastPieceChunk = pieceChunks.getLast();
            nextChunkPieceBuffer.add(lastPieceChunk);
            nextChunkSize += lastPieceChunk.length();
        }
        nextChunkPieceBuffer.stream().reduce(Chunk::merge).ifPresent(chunks::add);
        chunks = mergeChunksWithOverlap(chunks, maxChunkSize, maxOverlapSize);
        if (parentMetadata.isEmpty()) {
            return chunks;
        }
        return chunks.stream().filter(Predicate.not(Chunk::isEmpty)).map(chunk -> {
            HashMap<String, String> metadata = new HashMap<>(parentMetadata);
            metadata.putAll(chunk.metadata);
            return new Chunk(chunk.piece(), Collections.unmodifiableMap(metadata));
        }).toList();
    }

    private static List<Chunk> mergeChunksWithOverlap(List<Chunk> pieces, int maxChunkSize, int maxOverlapSize) {
        List<Chunk> chunks = new ArrayList<>();
        List<Chunk> mergeBuffer = new ArrayList<>();
        int mergeBufferSize = 0;
        Chunk lastChunk = Chunk.EMPTY;
        for (Chunk piece : pieces) {
            if (piece.length() > maxChunkSize) {
                Chunk remainder = piece;
                while (remainder.length() > maxChunkSize) {
                    // TODO: need to figure out a way to properly link these pieces
                    Chunk part = new Chunk(remainder.piece().substring(0, maxChunkSize), remainder.metadata);
                    chunks.add(part);
                    remainder = new Chunk(remainder.piece().substring(maxChunkSize, remainder.length()), remainder.metadata);
                }
                piece = remainder;
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

    record Chunk(String piece, Map<String, String> metadata) {

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
    }

    interface Splitter {

        Iterator<Chunk> split(String content);
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
                private boolean nextIsDelimiter = false;

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
                            nextIsDelimiter = false;
                            lastIndex = delimiterStart;
                            hasNextPiece = true;
                            return;
                        }

                        // Next piece is the delimiter itself
                        nextPiece = content.substring(delimiterStart, delimiterEnd);
                        nextIsDelimiter = true;
                        lastIndex = delimiterEnd;
                        hasNextPiece = true;
                        return;
                    }

                    if (lastIndex < content.length()) {
                        // Remaining content after last delimiter
                        nextPiece = content.substring(lastIndex);
                        nextIsDelimiter = false;
                        lastIndex = content.length();
                        hasNextPiece = true;
                        finished = true;
                    } else {
                        hasNextPiece = false;
                        finished = true;
                    }
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

    static class HeaderSplitter implements Splitter {

        private final Pattern headerPattern;

        HeaderSplitter(int level) {
            this.headerPattern = Pattern.compile(String.format("\n#{%d} (.*)\n", level));
        }

        @Override
        public Iterator<Chunk> split(String content) {
            return new Iterator<>() {
                private int lastIndex = 0;
                private String nextPiece = null;
                private Map<String, String> nextPieceMetadata = Map.of();
                private boolean hasNextPiece = false;
                private boolean finished = false;
                private String lastHeader = null;

                private void prepareNext() {
                    if (finished) {
                        return;
                    }
                    Matcher matcher = headerPattern.matcher(content.substring(lastIndex));
                    if (matcher.find()) {
                        int delimiterStart = matcher.start() + lastIndex;
                        int delimiterEnd = matcher.end() + lastIndex;
                        if (delimiterStart > lastIndex) {
                            // Next piece is the content before the delimiter
                            nextPiece = content.substring(lastIndex, delimiterStart);
                            lastIndex = delimiterStart;
                            hasNextPiece = true;
                            if (lastHeader != null) {
                                nextPieceMetadata = Map.of("header", lastHeader);
                            } else {
                                nextPieceMetadata = Map.of();
                            }
                            return;
                        }
                        // Next piece is the delimiter itself
                        nextPiece = content.substring(delimiterStart, delimiterEnd);
                        lastHeader = matcher.group(1);
                        nextPieceMetadata = Map.of("header", lastHeader);
                        lastIndex = delimiterEnd;
                        hasNextPiece = true;
                        return;
                    }
                    if (lastIndex < content.length()) {
                        // TODO: set metadata for rest
                        nextPiece = content.substring(lastIndex);
                        lastIndex = content.length();
                        hasNextPiece = true;
                        if (lastHeader != null) {
                            nextPieceMetadata = Map.of("header", lastHeader);
                        } else {
                            nextPieceMetadata = Map.of();
                        }
                        finished = true;
                    } else {
                        hasNextPiece = false;
                        finished = true;
                    }
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
                    return new Chunk(nextPiece, nextPieceMetadata);
                }
            };
        }
    }

// FIXME: remove ## from header metadata

}
