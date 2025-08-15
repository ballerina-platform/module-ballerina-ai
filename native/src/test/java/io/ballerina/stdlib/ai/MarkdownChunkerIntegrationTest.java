package io.ballerina.stdlib.ai;

import org.testng.annotations.Test;
import org.testng.annotations.DataProvider;
import static org.testng.Assert.*;

import dev.langchain4j.data.segment.TextSegment;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.stream.Collectors;
import java.util.Map;

public class MarkdownChunkerIntegrationTest {

    private static final int CHUNK_SIZE = 500;
    private static final int MAX_OVERLAP_SIZE = 50;
    private static final String INPUT_DIR = "markdown-chunker-test/input";
    private static final String EXPECTED_DIR = "markdown-chunker-test/expected";

    @DataProvider(name = "markdownFiles")
    public Object[][] markdownFiles() {
        return new Object[][]{
            {"sample1.md"},
            {"sample2.md"},
            {"sample3.md"},
            {"sample4.md"},
            {"sample5.md"},
            {"sample6.md"}
        };
    }

    @Test
    public void test() throws IOException {
       String fileName = "sample4.md";
        String inputContent = loadFileContent(INPUT_DIR + "/" + fileName);
        List<TextSegment> chunks = MarkdownChunker.chunk(inputContent, CHUNK_SIZE, MAX_OVERLAP_SIZE);
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
        assertEquals(actualOutput, expectedOutput, 
            "Chunking output for " + fileName + " does not match expected result");
    }

    @Test(dataProvider = "markdownFiles")
    public void testMarkdownChunkingWithoutOverlap(String fileName) throws IOException {
        // Load input markdown file
        String inputContent = loadFileContent(INPUT_DIR + "/" + fileName);

        // Chunk the content using MarkdownChunker
        List<TextSegment> chunks = MarkdownChunker.chunk(inputContent, CHUNK_SIZE, 0);
        String combinedChunks = chunks.stream().map(TextSegment::text).collect(Collectors.joining());
        assertEquals(combinedChunks, inputContent,
                "Chunking without overlap should return the original content for " + fileName);

        String actualOutput = formatChunksOutput(chunks, CHUNK_SIZE, 0);

        // Handle BLESS environment variable and expected file comparison
        String expectedFileName = fileName.replace(".md", "_" + CHUNK_SIZE + "_" + 0 + ".txt");
        String expectedOutput = getExpectedOutput(expectedFileName, actualOutput);

        // Compare actual vs expected
        assertEquals(actualOutput, expectedOutput,
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
