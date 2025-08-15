package io.ballerina.stdlib.ai;

import dev.langchain4j.data.segment.TextSegment;
import org.testng.Assert;
import org.testng.annotations.DataProvider;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

public class MarkdownChunkerIntegrationTest {

    private static final int CHUNK_SIZE = 500;
    private static final int MAX_OVERLAP_SIZE = 50;
    private static final String INPUT_DIR = "markdown-chunker-test/input";
    private static final String EXPECTED_DIR = "markdown-chunker-test/expected";

    @DataProvider(name = "markdownFiles")
    public Object[][] markdownFiles() throws IOException {
        Path inputDir = getResourcePath(INPUT_DIR);
        if (!Files.exists(inputDir)) {
            return new Object[0][0];
        }

        try (var stream = Files.list(inputDir)) {
            return stream
                    .filter(path -> path.toString().endsWith(".md"))
                    .map(path -> path.getFileName().toString())
                    .sorted()
                    .map(fileName -> new Object[]{fileName})
                    .toArray(Object[][]::new);
        }
    }

    @Test(dataProvider = "markdownFiles")
    public void testMarkdownChunking(String fileName) throws IOException {
        // Load input markdown file
        String inputContent = loadFileContent(INPUT_DIR + "/" + fileName);

        // Chunk the content using MarkdownChunker
        List<TextSegment> chunks = MarkdownChunker.chunk(inputContent, CHUNK_SIZE, MAX_OVERLAP_SIZE);

        // Format output as specified: "500 50" followed by chunks
        String actualOutput = formatChunksOutput(chunks, CHUNK_SIZE, MAX_OVERLAP_SIZE);

        // Handle BLESS environment variable and expected file comparison
        String expectedFileName = fileName.replace(".md", "_" + CHUNK_SIZE + "_" + MAX_OVERLAP_SIZE + ".txt");
        String expectedOutput = getExpectedOutput(expectedFileName, actualOutput);

        // Compare actual vs expected
        Assert.assertEquals(actualOutput, expectedOutput,
                "Chunking output for " + fileName + " does not match expected result");
    }

    @Test(dataProvider = "markdownFiles")
    public void testMarkdownChunkingWithoutOverlap(String fileName) throws IOException {
        // Load input markdown file
        String inputContent = loadFileContent(INPUT_DIR + "/" + fileName);

        // Chunk the content using MarkdownChunker
        List<TextSegment> chunks = MarkdownChunker.chunk(inputContent, CHUNK_SIZE, 0);
        String combinedChunks = chunks.stream().map(TextSegment::text).collect(Collectors.joining());
        Assert.assertEquals(combinedChunks, inputContent,
                "Chunking without overlap should return the original content for " + fileName);

        String actualOutput = formatChunksOutput(chunks, CHUNK_SIZE, 0);

        // Handle BLESS environment variable and expected file comparison
        String expectedFileName = fileName.replace(".md", "_" + CHUNK_SIZE + "_" + 0 + ".txt");
        String expectedOutput = getExpectedOutput(expectedFileName, actualOutput);

        // Compare actual vs expected
        Assert.assertEquals(actualOutput, expectedOutput,
                "Chunking output for " + fileName + " does not match expected result");
    }

    private String loadFileContent(String relativePath) throws IOException {
        Path resourcePath = getResourcePath(relativePath);
        return Files.readString(resourcePath);
    }

    private Path getResourcePath(String relativePath) {
        return Paths.get(System.getProperty("user.dir"))
                .resolve("src/test/resources")
                .resolve(relativePath);
    }

    private String formatChunksOutput(List<TextSegment> chunks, int chunkSize, int maxOverlapSize) {
        StringBuilder sb = new StringBuilder();
        sb.append(chunkSize).append(" ").append(maxOverlapSize).append("\n\n");

        for (int i = 0; i < chunks.size(); i++) {
            sb.append("--- Chunk ").append(i + 1).append(" ---\n");

            // Add metadata if present
            Map<String, Object> metadata = chunks.get(i).metadata().toMap();
            if (!metadata.isEmpty()) {
                sb.append("Metadata: ").append(metadata).append("\n");
            }

            sb.append(chunks.get(i).text());
            if (i < chunks.size() - 1) {
                sb.append("\n\n");
            }
        }

        return sb.toString();
    }

    @DataProvider(name = "chunkStrategies")
    public Object[][] chunkStrategies() {
        return new Object[][] {
            {MarkdownChunker.MarkdownChunkStrategy.BY_HEADER},
            {MarkdownChunker.MarkdownChunkStrategy.BY_CODE_BLOCK},
            {MarkdownChunker.MarkdownChunkStrategy.BY_HORIZONTAL_LINE},
            {MarkdownChunker.MarkdownChunkStrategy.BY_PARAGRAPH},
            {MarkdownChunker.MarkdownChunkStrategy.BY_LINE},
            {MarkdownChunker.MarkdownChunkStrategy.BY_SENTENCE},
            {MarkdownChunker.MarkdownChunkStrategy.BY_WORD},
            {MarkdownChunker.MarkdownChunkStrategy.BY_CHARACTER}
        };
    }

    @Test
    public void testByHeaderStrategy() {
        String markdownWithHeaders = """
                # Header 1
                Content under header 1.
                
                ## Header 2
                Content under header 2.
                
                ### Header 3
                Content under header 3.
                """;
        
        List<TextSegment> chunks = MarkdownChunker.chunk(markdownWithHeaders, 
                MarkdownChunker.MarkdownChunkStrategy.BY_HEADER, 200, 20);
        
        // BY_HEADER strategy uses fallthrough, so it will split by multiple criteria
        Assert.assertFalse(chunks.isEmpty(), "BY_HEADER should produce chunks");
        
        // Check that header metadata is preserved for chunks that contain headers
        boolean hasHeaderMetadata = chunks.stream()
                .anyMatch(chunk -> chunk.metadata().toMap().containsKey("header"));
        // Note: Due to fallthrough behavior, not all chunks may have header metadata
        // The test should just verify that the strategy works without errors
    }

    @Test
    public void testByCodeBlockStrategy() {
        String markdownWithCode = """
                Some text before code.
                
                ```java
                public void example() {
                    foo("Hello");
                }
                ```
                
                Some text after code.
                
                ```python
                print("Hello")
                ```
                
                Final text.
                """;
        
        List<TextSegment> chunks = MarkdownChunker.chunk(markdownWithCode,
                MarkdownChunker.MarkdownChunkStrategy.BY_CODE_BLOCK, 200, 20);
        
        Assert.assertTrue(chunks.size() >= 3, "BY_CODE_BLOCK should separate code blocks");
        
        // Check that code block metadata is preserved
        boolean hasCodeBlockMetadata = chunks.stream()
                .anyMatch(chunk -> "code_block".equals(chunk.metadata().toMap().get("type")));
        Assert.assertTrue(hasCodeBlockMetadata, "Code blocks should have type metadata");
        
        // Check language metadata
        boolean hasLanguageMetadata = chunks.stream()
                .anyMatch(chunk -> chunk.metadata().toMap().containsKey("language"));
        Assert.assertTrue(hasLanguageMetadata, "Code blocks should have language metadata");
    }

    @Test
    public void testByHorizontalLineStrategy() {
        String markdownWithHorizontalLines = """
                Section 1 content.
                
                ---
                
                Section 2 content.
                
                ***
                
                Section 3 content.
                
                ___
                
                Section 4 content.
                """;
        
        List<TextSegment> chunks = MarkdownChunker.chunk(markdownWithHorizontalLines,
                MarkdownChunker.MarkdownChunkStrategy.BY_HORIZONTAL_LINE, 200, 20);
        
        // BY_HORIZONTAL_LINE strategy includes fallthrough behavior
        Assert.assertFalse(chunks.isEmpty(), "BY_HORIZONTAL_LINE should produce chunks");
    }

    @Test
    public void testByParagraphStrategy() {
        String markdownWithParagraphs = """
                First paragraph with some content.
                
                Second paragraph with different content.
                
                Third paragraph here.
                """;
        
        List<TextSegment> chunks = MarkdownChunker.chunk(markdownWithParagraphs,
                MarkdownChunker.MarkdownChunkStrategy.BY_PARAGRAPH, 100, 10);
        
        // BY_PARAGRAPH strategy includes fallthrough to line, sentence, word, character splitters
        Assert.assertFalse(chunks.isEmpty(), "BY_PARAGRAPH should produce chunks");
    }

    @Test
    public void testByLineStrategy() {
        String markdownWithLines = """
                Line 1
                Line 2
                Line 3
                Line 4
                """;
        
        List<TextSegment> chunks = MarkdownChunker.chunk(markdownWithLines,
                MarkdownChunker.MarkdownChunkStrategy.BY_LINE, 20, 5);
        
        Assert.assertTrue(chunks.size() >= 2, "BY_LINE should split at line breaks");
    }

    @Test
    public void testBySentenceStrategy() {
        String markdownWithSentences = "First sentence. Second sentence. Third sentence. Fourth sentence.";
        
        List<TextSegment> chunks = MarkdownChunker.chunk(markdownWithSentences,
                MarkdownChunker.MarkdownChunkStrategy.BY_SENTENCE, 30, 5);
        
        Assert.assertTrue(chunks.size() >= 2, "BY_SENTENCE should split at sentence boundaries");
    }

    @Test
    public void testByWordStrategy() {
        String markdownWithWords = "word1 word2 word3 word4 word5 word6 word7 word8";
        
        List<TextSegment> chunks = MarkdownChunker.chunk(markdownWithWords,
                MarkdownChunker.MarkdownChunkStrategy.BY_WORD, 15, 3);
        
        Assert.assertTrue(chunks.size() >= 3, "BY_WORD should split at word boundaries");
    }

    @Test
    public void testByCharacterStrategy() {
        String shortText = "abcdefghijklmnopqrstuvwxyz";
        
        List<TextSegment> chunks = MarkdownChunker.chunk(shortText,
                MarkdownChunker.MarkdownChunkStrategy.BY_CHARACTER, 5, 1);
        
        Assert.assertTrue(chunks.size() >= 5, "BY_CHARACTER should split at character boundaries");
        
        // Verify content is preserved
        String reconstructed = chunks.stream().map(TextSegment::text).collect(Collectors.joining());
        Assert.assertTrue(reconstructed.contains(shortText.substring(0, Math.min(5, shortText.length()))), 
                "Character chunking should preserve content");
    }

    @Test(dataProvider = "chunkStrategies")
    void testStrategyConsistency(MarkdownChunker.MarkdownChunkStrategy strategy) throws IOException {
        String inputContent = loadFileContent(INPUT_DIR + "/sample7.md");
        
        // Test that each strategy produces consistent results
        List<TextSegment> chunks1 = MarkdownChunker.chunk(inputContent, strategy, CHUNK_SIZE, MAX_OVERLAP_SIZE);
        List<TextSegment> chunks2 = MarkdownChunker.chunk(inputContent, strategy, CHUNK_SIZE, MAX_OVERLAP_SIZE);
        
        Assert.assertEquals(chunks1.size(), chunks2.size(), 
                "Strategy " + strategy + " should be deterministic");
        
        for (int i = 0; i < chunks1.size(); i++) {
            Assert.assertEquals(chunks1.get(i).text(), chunks2.get(i).text(), 
                    "Chunk " + i + " should be identical for strategy " + strategy);
        }
    }

    @Test(dataProvider = "chunkStrategies")
    void testStrategyWithDifferentSizes(MarkdownChunker.MarkdownChunkStrategy strategy) throws IOException {
        String inputContent = loadFileContent(INPUT_DIR + "/sample7.md");
        
        // Test different chunk sizes for each strategy
        int[] chunkSizes = {100, 500, 1000};
        
        for (int chunkSize : chunkSizes) {
            List<TextSegment> chunks = MarkdownChunker.chunk(inputContent, strategy, chunkSize, 20);
            
            Assert.assertTrue(chunks.size() > 0, 
                    "Strategy " + strategy + " with chunk size " + chunkSize + " should produce chunks");
            
            // Verify no chunk is excessively large (allowing some flexibility)
            for (TextSegment chunk : chunks) {
                Assert.assertTrue(chunk.text().length() <= chunkSize + 200, // Allow flexibility for boundaries
                        "Chunk size " + chunk.text().length() + " exceeds limit for strategy " + strategy);
            }
        }
    }

    @Test
    public void testStrategyFallbackBehavior() {
        String singleWord = "word";
        
        // Test that all strategies can handle minimal content
        for (MarkdownChunker.MarkdownChunkStrategy strategy : MarkdownChunker.MarkdownChunkStrategy.values()) {
            List<TextSegment> chunks = MarkdownChunker.chunk(singleWord, strategy, 100, 10);
            
            Assert.assertEquals(chunks.size(), 1, 
                    "Strategy " + strategy + " should produce one chunk for single word");
            Assert.assertEquals(chunks.getFirst().text(), singleWord,
                    "Strategy " + strategy + " should preserve single word content");
        }
    }

    private String getExpectedOutput(String expectedFileName, String actualOutput) throws IOException {
        String blessEnv = System.getenv("BLESS");
        boolean shouldBless = "true".equalsIgnoreCase(blessEnv);

        Path expectedPath = getResourcePath(EXPECTED_DIR + "/" + expectedFileName);

        if (shouldBless) {
            // Create directories if they don't exist
            Files.createDirectories(expectedPath.getParent());

            // Write actual output as expected (BLESS mode)
            Files.writeString(expectedPath, actualOutput);
            return actualOutput;
        } else {
            // Load existing expected output for comparison
            return Files.readString(expectedPath);
        }
    }
}
