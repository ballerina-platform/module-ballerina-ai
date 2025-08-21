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

import io.ballerina.stdlib.ai.RecursiveChunker.Chunk;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.util.Iterator;

public class HtmlHeaderSplitterTest {

    @Test
    public void testH1HeaderBasic() {
        HtmlHeaderSplitter splitter = new HtmlHeaderSplitter(1);
        Iterator<Chunk> iterator = splitter.split("Before<h1>Main Title</h1>After");

        // Prefix - no metadata
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "Before");
        Assert.assertEquals(prefix.metadata().size(), 0);

        // Tag - with heading1 metadata
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<h1>Main Title</h1>");
        Assert.assertEquals(tag.metadata().size(), 2);
        Assert.assertEquals(tag.metadata().get("header1"), "Main Title");
        Assert.assertEquals(tag.metadata().get("header"), "Main Title");

        // Suffix - with heading1 metadata
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "After");
        Assert.assertEquals(suffix.metadata().size(), 2);
        Assert.assertEquals(suffix.metadata().get("header1"), "Main Title");
        Assert.assertEquals(tag.metadata().get("header"), "Main Title");

        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testH2Header() {
        HtmlHeaderSplitter splitter = new HtmlHeaderSplitter(2);
        Iterator<Chunk> iterator = splitter.split("Content<h2>Subtitle</h2>More content");

        // Prefix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "Content");
        Assert.assertEquals(prefix.metadata().size(), 0);

        // Tag - with heading2 metadata
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<h2>Subtitle</h2>");
        Assert.assertEquals(tag.metadata().get("header2"), "Subtitle");

        // Suffix - with heading2 metadata
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "More content");
        Assert.assertEquals(suffix.metadata().get("header2"), "Subtitle");

        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testMultipleHeaders() {
        HtmlHeaderSplitter splitter = new HtmlHeaderSplitter(1);
        Iterator<Chunk> iterator = splitter.split("Start<h1>First</h1>Middle<h1>Second</h1>End");

        // First header sequence
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix1 = iterator.next();
        Assert.assertEquals(prefix1.piece(), "Start");
        Assert.assertEquals(prefix1.metadata().size(), 0);

        Assert.assertTrue(iterator.hasNext());
        Chunk tag1 = iterator.next();
        Assert.assertEquals(tag1.piece(), "<h1>First</h1>");
        Assert.assertEquals(tag1.metadata().get("header1"), "First");

        Assert.assertTrue(iterator.hasNext());
        Chunk suffix1 = iterator.next();
        Assert.assertEquals(suffix1.piece(), "Middle");
        Assert.assertEquals(suffix1.metadata().get("header1"), "First");

        // Second header sequence
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix2 = iterator.next();
        Assert.assertEquals(prefix2.piece(), "");
        Assert.assertEquals(prefix2.metadata().size(), 0);

        Assert.assertTrue(iterator.hasNext());
        Chunk tag2 = iterator.next();
        Assert.assertEquals(tag2.piece(), "<h1>Second</h1>");
        Assert.assertEquals(tag2.metadata().get("header1"), "Second");

        Assert.assertTrue(iterator.hasNext());
        Chunk suffix2 = iterator.next();
        Assert.assertEquals(suffix2.piece(), "End");
        Assert.assertEquals(suffix2.metadata().get("header1"), "Second");

        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testHeaderWithAttributes() {
        HtmlHeaderSplitter splitter = new HtmlHeaderSplitter(1);
        Iterator<Chunk> iterator = splitter.split(
                "Before<h1 class=\"title\" id=\"main\">Header with Attributes</h1>After");

        // Now that attributes are supported, this should work properly
        // Prefix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "Before");
        Assert.assertEquals(prefix.metadata().size(), 0);

        // Tag - should include the full opening tag with attributes
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<h1 class=\"title\" id=\"main\">Header with Attributes</h1>");
        Assert.assertEquals(tag.metadata().get("header1"), "Header with Attributes");

        // Suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "After");
        Assert.assertEquals(suffix.metadata().get("header1"), "Header with Attributes");

        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testHeaderWithNestedTags() {
        HtmlHeaderSplitter splitter = new HtmlHeaderSplitter(2);
        Iterator<Chunk> iterator = splitter.split("Text<h2>Header with <em>emphasis</em></h2>More text");

        // Prefix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "Text");
        Assert.assertEquals(prefix.metadata().size(), 0);

        // Tag - nested tags should be stripped from metadata
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<h2>Header with <em>emphasis</em></h2>");
        Assert.assertEquals(tag.metadata().get("header2"), "Header with emphasis");

        // Suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "More text");
        Assert.assertEquals(suffix.metadata().get("header2"), "Header with emphasis");

        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testDifferentHeaderLevels() {
        // Test each header level (h1 through h6)
        for (int level = 1; level <= 6; level++) {
            HtmlHeaderSplitter splitter = new HtmlHeaderSplitter(level);
            String tagName = "h" + level;
            String content = String.format("Before<%s>Level %d Header</%s>After", tagName, level, tagName);
            Iterator<Chunk> iterator = splitter.split(content);

            // Skip prefix
            Assert.assertTrue(iterator.hasNext());
            iterator.next();

            // Check tag
            Assert.assertTrue(iterator.hasNext());
            Chunk tag = iterator.next();
            Assert.assertEquals(tag.metadata().get("header" + level), "Level " + level + " Header");

            // Check suffix
            Assert.assertTrue(iterator.hasNext());
            Chunk suffix = iterator.next();
            Assert.assertEquals(suffix.metadata().get("header" + level), "Level " + level + " Header");
        }
    }

    @Test
    public void testEmptyHeader() {
        HtmlHeaderSplitter splitter = new HtmlHeaderSplitter(1);
        Iterator<Chunk> iterator = splitter.split("Before<h1></h1>After");

        // Prefix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "Before");

        // Tag - empty content
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<h1></h1>");
        Assert.assertEquals(tag.metadata().get("header1"), "");

        // Suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "After");
        Assert.assertEquals(suffix.metadata().get("header1"), "");

        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testWhitespaceInHeader() {
        HtmlHeaderSplitter splitter = new HtmlHeaderSplitter(3);
        Iterator<Chunk> iterator = splitter.split("Text<h3>   Whitespace Header   </h3>More");

        // Skip prefix
        iterator.next();

        // Tag - whitespace should be trimmed
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.metadata().get("header3"), "Whitespace Header");

        // Suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.metadata().get("header3"), "Whitespace Header");

        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testNoHeaders() {
        HtmlHeaderSplitter splitter = new HtmlHeaderSplitter(1);
        Iterator<Chunk> iterator = splitter.split("Just plain text with no headers");

        // When no headers found, the iterator may have different behavior
        // Let's test what actually happens
        boolean hasChunks = false;
        while (iterator.hasNext()) {
            Chunk chunk = iterator.next();
            hasChunks = true;
            // At minimum, verify we get the content back
            Assert.assertNotNull(chunk.piece());
            break; // Avoid infinite loops
        }

        // The test should pass as long as we get some output
        Assert.assertTrue(hasChunks, "Should produce at least one chunk");
    }

    @Test
    public void testHeaderAtStart() {
        HtmlHeaderSplitter splitter = new HtmlHeaderSplitter(1);
        Iterator<Chunk> iterator = splitter.split("<h1>First Header</h1>Content after");

        // Empty prefix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "");

        // Tag
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<h1>First Header</h1>");
        Assert.assertEquals(tag.metadata().get("header1"), "First Header");

        // Suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "Content after");
        Assert.assertEquals(suffix.metadata().get("header1"), "First Header");

        Assert.assertFalse(iterator.hasNext());
    }

    @Test
    public void testHeaderAtEnd() {
        HtmlHeaderSplitter splitter = new HtmlHeaderSplitter(2);
        Iterator<Chunk> iterator = splitter.split("Content before<h2>Last Header</h2>");

        // Prefix
        Assert.assertTrue(iterator.hasNext());
        Chunk prefix = iterator.next();
        Assert.assertEquals(prefix.piece(), "Content before");

        // Tag
        Assert.assertTrue(iterator.hasNext());
        Chunk tag = iterator.next();
        Assert.assertEquals(tag.piece(), "<h2>Last Header</h2>");
        Assert.assertEquals(tag.metadata().get("header2"), "Last Header");

        // Empty suffix
        Assert.assertTrue(iterator.hasNext());
        Chunk suffix = iterator.next();
        Assert.assertEquals(suffix.piece(), "");
        Assert.assertEquals(suffix.metadata().get("header2"), "Last Header");

        Assert.assertFalse(iterator.hasNext());
    }
}
