package io.ballerina.stdlib.ai;

import org.testng.Assert;
import org.testng.annotations.Test;

import java.util.Iterator;
import io.ballerina.stdlib.ai.RecursiveChunker.Chunk;

public class HTMLParagraphSplitterTest {

    @Test
    public void testBasicParagraph() {
        HTMLParagraphSplitter splitter = new HTMLParagraphSplitter();
        Iterator<Chunk> iterator = splitter.split("Before<p>Paragraph content</p>After");
        
        // Prefix - no metadata
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "Before");
        Assert.assertEquals(prefix.metadata().size(), 0);
        
        // Tag - no metadata
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<p>Paragraph content</p>");
        Assert.assertEquals(tag.metadata().size(), 0);
        
        // Suffix - no metadata
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "After");
        Assert.assertEquals(suffix.metadata().size(), 0);
        
        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testMultipleParagraphs() {
        HTMLParagraphSplitter splitter = new HTMLParagraphSplitter();
        Iterator<Chunk> iterator = splitter.split("Start<p>First paragraph</p>Middle<p>Second paragraph</p>End");
        
        // First paragraph sequence
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix1 = iterator.next();
        Assert.assertEquals(prefix1.piece(), "Start");
        Assert.assertEquals(prefix1.metadata().size(), 0);
        
        Assert.assertTrue(iterator.hasNext());
        Chunk tag1 = iterator.next();
        Assert.assertEquals(tag1.piece(), "<p>First paragraph</p>");
        Assert.assertEquals(tag1.metadata().size(), 0);
        
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix1 = iterator.next();
        Assert.assertEquals(suffix1.piece(), "Middle");
        Assert.assertEquals(suffix1.metadata().size(), 0);
        
        // Second paragraph sequence
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix2 = iterator.next();
        Assert.assertEquals(prefix2.piece(), "");
        Assert.assertEquals(prefix2.metadata().size(), 0);
        
        Assert.assertTrue(iterator.hasNext());
        Chunk tag2 = iterator.next();
        Assert.assertEquals(tag2.piece(), "<p>Second paragraph</p>");
        Assert.assertEquals(tag2.metadata().size(), 0);
        
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix2 = iterator.next();
        Assert.assertEquals(suffix2.piece(), "End");
        Assert.assertEquals(suffix2.metadata().size(), 0);
        
        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testParagraphWithAttributes() {
        HTMLParagraphSplitter splitter = new HTMLParagraphSplitter();
        Iterator<Chunk> iterator = splitter.split("Before<p class=\"intro\" id=\"first\">Paragraph with attributes</p>After");
        
        // Should properly handle opening tag with attributes
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "Before");
        
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<p class=\"intro\" id=\"first\">Paragraph with attributes</p>");
        Assert.assertEquals(tag.metadata().size(), 0);
        
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "After");
        
        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testParagraphWithNestedTags() {
        HTMLParagraphSplitter splitter = new HTMLParagraphSplitter();
        Iterator<Chunk> iterator = splitter.split("Text<p>Paragraph with <strong>bold</strong> text</p>More text");
        
        // Prefix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "Text");
        Assert.assertEquals(prefix.metadata().size(), 0);
        
        // Tag - nested tags should remain in content
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<p>Paragraph with <strong>bold</strong> text</p>");
        Assert.assertEquals(tag.metadata().size(), 0);
        
        // Suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "More text");
        Assert.assertEquals(suffix.metadata().size(), 0);
        
        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testEmptyParagraph() {
        HTMLParagraphSplitter splitter = new HTMLParagraphSplitter();
        Iterator<Chunk> iterator = splitter.split("Before<p></p>After");
        
        // Prefix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "Before");
        
        // Tag - empty content
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<p></p>");
        Assert.assertEquals(tag.metadata().size(), 0);
        
        // Suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "After");
        
        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testParagraphAtStart() {
        HTMLParagraphSplitter splitter = new HTMLParagraphSplitter();
        Iterator<Chunk> iterator = splitter.split("<p>First paragraph</p>Content after");
        
        // Empty prefix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "");
        
        // Tag
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<p>First paragraph</p>");
        Assert.assertEquals(tag.metadata().size(), 0);
        
        // Suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "Content after");
        
        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testParagraphAtEnd() {
        HTMLParagraphSplitter splitter = new HTMLParagraphSplitter();
        Iterator<Chunk> iterator = splitter.split("Content before<p>Last paragraph</p>");
        
        // Prefix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "Content before");
        
        // Tag
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<p>Last paragraph</p>");
        Assert.assertEquals(tag.metadata().size(), 0);
        
        // Empty suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "");
        
        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testNoParagraphs() {
        HTMLParagraphSplitter splitter = new HTMLParagraphSplitter();
        Iterator<Chunk> iterator = splitter.split("Just plain text with no paragraphs");
        
        // When no paragraphs found, should return the content as-is
        boolean hasChunks = false;
        while (iterator.hasNext()) {
            Chunk chunk = iterator.next();
            hasChunks = true;
            Assert.assertNotNull(chunk.piece());
            break; // Avoid infinite loops
        }
        
        Assert.assertTrue(hasChunks, "Should produce at least one chunk");
    }

    @Test
    public void testParagraphsAroundOtherTags() {
        HTMLParagraphSplitter splitter = new HTMLParagraphSplitter();
        Iterator<Chunk> iterator = splitter.split("<div>Div content</div><p>Paragraph content</p><span>Span content</span>");
        
        // Should get: prefix (including div tag), tag content, suffix (including span tag)
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "<div>Div content</div>");
        Assert.assertEquals(prefix.metadata().size(), 0);
        
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<p>Paragraph content</p>");
        Assert.assertEquals(tag.metadata().size(), 0);
        
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "<span>Span content</span>");
        Assert.assertEquals(suffix.metadata().size(), 0);
        
        Assert.assertFalse(iterator.hasNext());
    }
}