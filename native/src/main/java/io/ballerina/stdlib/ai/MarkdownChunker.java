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
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.IntStream;

class MarkdownChunker {

    // Types that should not be merged with other chunks
    private static final Set<String> NON_MERGEABLE_TYPES = Set.of("code_block");

    enum MarkdownChunkStrategy {
        BY_HEADER, BY_CODE_BLOCK, BY_HORIZONTAL_LINE, BY_PARAGRAPH, BY_LINE, BY_SENTENCE, BY_WORD, BY_CHARACTER;

        public List<Splitter> getSplitters() {
            List<Splitter> splitters = new ArrayList<>();

            switch (this) {
                case BY_HEADER:
                    splitters.addAll(List.of(
                            new HeaderSplitter(2),
                            new HeaderSplitter(3),
                            new HeaderSplitter(4),
                            new HeaderSplitter(5),
                            new HeaderSplitter(6)));
                case BY_CODE_BLOCK:
                    splitters.add(new CodeBlockSplitter());
                case BY_HORIZONTAL_LINE:
                    splitters.addAll(List.of(
                            new SimpleDelimiterSplitter("\n\\*\\*\\*+\n"),
                            new SimpleDelimiterSplitter("\\n---+\\n"),
                            new SimpleDelimiterSplitter("\n___+\n")));
                case BY_PARAGRAPH:
                    splitters.add(new SimpleDelimiterSplitter("\n\n"));
                case BY_LINE:
                    splitters.add(new SimpleDelimiterSplitter("\n"));
                case BY_SENTENCE:
                    splitters.add(new SimpleDelimiterSplitter("\\."));
                case BY_WORD:
                    splitters.add(new SimpleDelimiterSplitter(" "));
                case BY_CHARACTER:
                    splitters.add(new SimpleDelimiterSplitter(""));
            }

            return splitters;
        }
    }

    static List<TextSegment> chunk(String content, MarkdownChunkStrategy strategy, int maxChunkSize, int maxOverlapSize) {
        if (maxChunkSize <= 0) {
            throw new IllegalArgumentException("Chunk size must be greater than 0");
        }
        if (maxOverlapSize > maxChunkSize) {
            throw new IllegalArgumentException("Max overlap size must be less than or equal to chunk size");
        }
        List<Chunk> chunks = chunkUsingDelimiters(content, strategy.getSplitters(), maxChunkSize, maxOverlapSize);
        return IntStream.range(0, chunks.size())
                .mapToObj(i -> chunks.get(i).toTextSegment(i))
                .toList();
    }

    static List<TextSegment> chunk(String content, int chunkSize, int maxOverlapSize) {
        List<Chunk> chunks = chunkUsingDelimiters(content,
                        MarkdownChunkStrategy.BY_HEADER.getSplitters(), chunkSize,
                maxOverlapSize);
        return IntStream.range(0, chunks.size())
                .mapToObj(i -> chunks.get(i).toTextSegment(i))
                .toList();
    }

    private static List<Chunk> chunkUsingDelimiters(String content, List<Splitter> delimiters, int maxChunkSize,
                                                    int maxOverlapSize) {
        return chunkUsingDelimitersInner(content, delimiters, maxChunkSize, maxOverlapSize, Collections.emptyMap());
    }

    private static List<Chunk> chunkUsingDelimitersInner(String content, List<Splitter> delimiters, int maxChunkSize,
                                                         int maxOverlapSize, Map<String, String> parentMetadata) {
        List<Splitter> rest = delimiters.subList(1, delimiters.size());
        Iterator<Chunk> pieces = delimiters.getFirst().split(content);
        List<Chunk> chunks = new ArrayList<>();
        List<Chunk> nextChunkPieceBuffer = new ArrayList<>();
        int nextChunkSize = 0;
        while (pieces.hasNext()) {
            Chunk piece = pieces.next();

            // If this piece is non-mergeable, flush buffer and add it directly
            if (isNonMergeable(piece)) {
                // Flush current buffer
                nextChunkPieceBuffer.stream().reduce(Chunk::merge).ifPresent(chunks::add);
                nextChunkPieceBuffer.clear();
                nextChunkSize = 0;

                // Add non-mergeable piece directly
                if (piece.length() > maxChunkSize) {
                    chunks.addAll(breakUpChunk(piece, maxChunkSize));
                } else {
                    chunks.add(piece);
                }
                continue;
            }

            if (nextChunkSize + piece.length() <= maxChunkSize) {
                nextChunkPieceBuffer.add(piece);
                nextChunkSize += piece.length();
                continue;
            }

            nextChunkPieceBuffer.stream().reduce(Chunk::merge).ifPresent(chunks::add);
            nextChunkPieceBuffer.clear();
            nextChunkSize = 0;

            // If the piece is smaller than the max chunk size, just add it to the next chunk
            if (piece.length() <= maxChunkSize) {
                nextChunkPieceBuffer.add(piece);
                nextChunkSize += piece.length();
                continue;
            }

            // Break up the current piece
            List<Chunk> pieceChunks =
                    chunkUsingDelimitersInner(piece.piece, rest, maxChunkSize, maxOverlapSize, piece.metadata);
            chunks.addAll(pieceChunks.subList(0, pieceChunks.size() - 1));
            Chunk lastPieceChunk = pieceChunks.getLast();
            if (isNonMergeable(lastPieceChunk)) {
                // If the last piece is non-mergeable, add it directly
                chunks.add(lastPieceChunk);
            } else {
                nextChunkPieceBuffer.add(lastPieceChunk);
                nextChunkSize += lastPieceChunk.length();
            }
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

    private static boolean isNonMergeable(Chunk chunk) {
        if (!chunk.metadata().containsKey("type")) {
            return false;
        }
        String type = chunk.metadata().get("type");
        return NON_MERGEABLE_TYPES.contains(type);
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

    private static List<Chunk> mergeChunksWithOverlap(List<Chunk> pieces, int maxChunkSize, int maxOverlapSize) {
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

    static class HeaderSplitter implements Splitter {

        private final Pattern headerPattern;

        HeaderSplitter(int level) {
            this.headerPattern = Pattern.compile(String.format("\n#{%d} (.*)\n", level));
        }

        @Override
        public Iterator<Chunk> split(String content) {
            return new Iterator<>() {
                private final Matcher matcher = headerPattern.matcher(content);
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
                    matcher.region(lastIndex, content.length());
                    if (matcher.find()) {
                        int delimiterStart = matcher.start();
                        int delimiterEnd = matcher.end();
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
                        nextPiece = content.substring(lastIndex);
                        lastIndex = content.length();
                        hasNextPiece = true;
                        if (lastHeader != null) {
                            nextPieceMetadata = Map.of("header", lastHeader);
                        } else {
                            nextPieceMetadata = Map.of();
                        }
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
                    return new Chunk(nextPiece, nextPieceMetadata);
                }
            };
        }
    }

    static class CodeBlockSplitter implements Splitter {

        private final Pattern codeBlockStartPattern = Pattern.compile("```(\\w+)?\\n");
        private final Pattern codeBlockEndPattern = Pattern.compile("```\\n");

        @Override
        public Iterator<Chunk> split(String content) {
            return new Iterator<>() {
                private final Matcher startMatcher = codeBlockStartPattern.matcher(content);
                private final Matcher endMatcher = codeBlockEndPattern.matcher(content);
                private int lastIndex = 0;
                private String nextPiece = null;
                private Map<String, String> nextPieceMetadata = Map.of();
                private boolean hasNextPiece = false;
                private boolean finished = false;

                private void prepareNext() {
                    if (finished) {
                        return;
                    }

                    // Find the next code block start
                    startMatcher.region(lastIndex, content.length());
                    if (startMatcher.find()) {
                        int startIndex = startMatcher.start();
                        int startEndIndex = startMatcher.end();

                        // If there's content before the code block, return it first
                        if (startIndex > lastIndex) {
                            nextPiece = content.substring(lastIndex, startIndex);
                            nextPieceMetadata = Map.of();
                            lastIndex = startIndex;
                            hasNextPiece = true;
                            return;
                        }

                        // Extract the language from the code block start
                        String language = startMatcher.group(1);
                        if (language == null) {
                            language = "unknown";
                        }

                        // Find the end of this code block
                        endMatcher.region(startEndIndex, content.length());
                        if (endMatcher.find()) {
                            int endEndIndex = endMatcher.end();

                            // Extract the entire code block (including the start and end markers)
                            nextPiece = content.substring(startIndex, endEndIndex);
                            nextPieceMetadata = Map.of("language", language, "type", "code_block");
                            lastIndex = endEndIndex;
                            hasNextPiece = true;
                        } else {
                            // No end found, treat the rest as a code block
                            nextPiece = content.substring(startIndex);
                            nextPieceMetadata = Map.of("language", language, "type", "code_block");
                            lastIndex = content.length();
                            hasNextPiece = true;
                            finished = true;
                        }
                        return;
                    }

                    // No more code blocks, return remaining content
                    if (lastIndex < content.length()) {
                        nextPiece = content.substring(lastIndex);
                        nextPieceMetadata = Map.of();
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
                    return new Chunk(nextPiece, nextPieceMetadata);
                }
            };
        }
    }

}
