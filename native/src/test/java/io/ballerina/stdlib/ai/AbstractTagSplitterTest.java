package io.ballerina.stdlib.ai;

import org.testng.Assert;
import org.testng.annotations.Test;

import java.util.Iterator;
import io.ballerina.stdlib.ai.RecursiveChunker.Chunk;

public class AbstractTagSplitterTest {

    // Test implementation of AbstractTagSplitter
    static class TestTagSplitter extends AbstractTagSplitter {
        TestTagSplitter(String tagName) {
            super(tagName);
        }
    }

    @Test
    public void testSimpleHtml() {
        TestTagSplitter splitter = new TestTagSplitter("h1");
        Iterator<Chunk> iterator = splitter.split("Before<h1>Header Content</h1>After");
        
        // Should get: prefix, tag content, suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "Before");
        
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<h1>Header Content</h1>");
        
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "After");
        
        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testMultipleInstances() {
        TestTagSplitter splitter = new TestTagSplitter("p");
        Iterator<Chunk> iterator = splitter.split("Start<p>First</p>Middle<p>Second</p>End");
        
        // First tag: prefix, tag, suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix1 = iterator.next();
        Assert.assertEquals(prefix1.piece(), "Start");
        
        Assert.assertTrue(iterator.hasNext());
        Chunk tag1 = iterator.next();
        Assert.assertEquals(tag1.piece(), "<p>First</p>");
        
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix1 = iterator.next();
        Assert.assertEquals(suffix1.piece(), "Middle");
        
        // Second tag: prefix, tag, suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix2 = iterator.next();
        Assert.assertEquals(prefix2.piece(), "");
        
        Assert.assertTrue(iterator.hasNext());
        Chunk tag2 = iterator.next();
        Assert.assertEquals(tag2.piece(), "<p>Second</p>");
        
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix2 = iterator.next();
        Assert.assertEquals(suffix2.piece(), "End");
        
        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testNoPrefixNoSuffix() {
        TestTagSplitter splitter = new TestTagSplitter("h1");
        Iterator<Chunk> iterator = splitter.split("<h1>Just Header</h1>");
        
        // Should get: empty prefix, tag content, empty suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "");
        
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<h1>Just Header</h1>");
        
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "");
        
        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testNestedTags() {
        TestTagSplitter splitter = new TestTagSplitter("div");
        Iterator<Chunk> iterator = splitter.split("Before<div>Content <span>nested</span> more</div>After");
        
        // Should get: prefix, tag content (including nested span), suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "Before");
        
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<div>Content <span>nested</span> more</div>");
        
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "After");
        
        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testTagsAroundTarget() {
        TestTagSplitter splitter = new TestTagSplitter("h1");
        Iterator<Chunk> iterator = splitter.split("<p>Paragraph</p><h1>Header</h1><span>Span</span>");
        
        // Should get: prefix (including p tag), tag content, suffix (including span tag)
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "<p>Paragraph</p>");
        
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<h1>Header</h1>");
        
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "<span>Span</span>");
        
        Assert.assertFalse(iterator.hasNext());
    }

    @Test(expectedExceptions = IndexOutOfBoundsException.class)
    public void testUnclosedTag() {
        TestTagSplitter splitter = new TestTagSplitter("h1");
        Iterator<Chunk> iterator = splitter.split("Before<h1>Unclosed content");
        while (iterator.hasNext()) {
            iterator.next();
        }
    }
}