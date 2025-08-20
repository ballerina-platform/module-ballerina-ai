package io.ballerina.stdlib.ai;

import dev.langchain4j.data.segment.TextSegment;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.IntStream;

class MarkdownChunker {

    private static final Set<String> NON_MERGEABLE_TYPES = Set.of("code_block");

    enum MarkdownChunkStrategy {
        BY_HEADER, BY_CODE_BLOCK, BY_HORIZONTAL_LINE, BY_PARAGRAPH, BY_LINE, BY_SENTENCE, BY_WORD, BY_CHARACTER;

        public List<RecursiveChunker.Splitter> getSplitters() {
            List<RecursiveChunker.Splitter> splitters = new ArrayList<>();

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
                            new RecursiveChunker.SimpleDelimiterSplitter("\n\\*\\*\\*+\n"),
                            new RecursiveChunker.SimpleDelimiterSplitter("\\n---+\\n"),
                            new RecursiveChunker.SimpleDelimiterSplitter("\n___+\n")));
                case BY_PARAGRAPH:
                    splitters.add(new RecursiveChunker.SimpleDelimiterSplitter("\n\n"));
                case BY_LINE:
                    splitters.add(new RecursiveChunker.SimpleDelimiterSplitter("\n"));
                case BY_SENTENCE:
                    splitters.add(RecursiveChunker.Splitter.createSentenceSplitter());
                case BY_WORD:
                    splitters.add(RecursiveChunker.Splitter.createWordSplitter());
                case BY_CHARACTER:
                    splitters.add(RecursiveChunker.Splitter.createCharacterSplitter());
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
        RecursiveChunker chunker = new RecursiveChunker(NON_MERGEABLE_TYPES);
        List<RecursiveChunker.Chunk> chunks =
                chunker.chunkUsingSplitters(content, strategy.getSplitters(), maxChunkSize, maxOverlapSize);
        return IntStream.range(0, chunks.size()).mapToObj(i -> chunks.get(i).toTextSegment(i)).toList();
    }

    static List<TextSegment> chunk(String content, int chunkSize, int maxOverlapSize) {
        RecursiveChunker chunker = new RecursiveChunker(NON_MERGEABLE_TYPES);
        List<RecursiveChunker.Chunk> chunks =
                chunker.chunkUsingSplitters(content, MarkdownChunkStrategy.BY_HEADER.getSplitters(), chunkSize,
                        maxOverlapSize);
        return IntStream.range(0, chunks.size()).mapToObj(i -> chunks.get(i).toTextSegment(i)).toList();
    }

    static class HeaderSplitter implements RecursiveChunker.Splitter {

        private final Pattern headerPattern;

        HeaderSplitter(int level) {
            this.headerPattern = Pattern.compile(String.format("\n#{%d} (.*)\n", level));
        }

        @Override
        public Iterator<RecursiveChunker.Chunk> split(String content) {
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
                public RecursiveChunker.Chunk next() {
                    if (!hasNext()) {
                        throw new java.util.NoSuchElementException();
                    }
                    hasNextPiece = false;
                    return new RecursiveChunker.Chunk(nextPiece, nextPieceMetadata);
                }
            };
        }
    }

    static class CodeBlockSplitter implements RecursiveChunker.Splitter {

        private final Pattern codeBlockStartPattern = Pattern.compile("```(\\w+)?\\n");
        private final Pattern codeBlockEndPattern = Pattern.compile("```\\n");

        @Override
        public Iterator<RecursiveChunker.Chunk> split(String content) {
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
                public RecursiveChunker.Chunk next() {
                    if (!hasNext()) {
                        throw new java.util.NoSuchElementException();
                    }
                    hasNextPiece = false;
                    return new RecursiveChunker.Chunk(nextPiece, nextPieceMetadata);
                }
            };
        }
    }

}
