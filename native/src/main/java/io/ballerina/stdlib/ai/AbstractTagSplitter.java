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

import java.util.Iterator;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import io.ballerina.stdlib.ai.RecursiveChunker.Chunk;

abstract class AbstractTagSplitter implements RecursiveChunker.Splitter {

    private final String tagName;
    private final Pattern openTagPattern;
    private final Pattern closeTagPattern;

    AbstractTagSplitter(String tagName) {
        this.tagName = tagName;
        this.openTagPattern = Pattern.compile("<" + tagName + ">");
        this.closeTagPattern = Pattern.compile("</" + tagName + ">");
    }

    @Override
    public Iterator<Chunk> split(String content) {
        return new TagSplitterIterator(content);
    }

    enum SplitterState {
        INIT, PREFIX, TAG, SUFFIX, END
    }

    private class TagSplitterIterator implements Iterator<Chunk> {

        private String content;
        private SplitterState currentState;
        // Part before the tag
        private String prefix;
        // Part between open and closing tags
        private String tag;
        // Part after closing tag but before the next opening tag
        private String suffix;

        TagSplitterIterator(String content) {
            assert content != null;
            this.content = content;
            this.currentState = SplitterState.INIT;
        }

        @Override
        public boolean hasNext() {
            if (currentState == SplitterState.INIT) {
                breakdownContent();
                assert currentState != SplitterState.INIT;
                return hasNext();
            }
            return currentState != SplitterState.END || !content.isEmpty();
        }

        @Override
        public Chunk next() {
            if (!hasNext()) {
                throw new NoSuchElementException();
            }
            return switch (currentState) {
                case INIT:
                    breakdownContent();
                    yield next();
                case PREFIX:
                    currentState = SplitterState.TAG;
                    yield new Chunk(prefix, Map.of());
                case TAG:
                    currentState = SplitterState.SUFFIX;
                    yield new Chunk(tag, Map.of());
                case SUFFIX:
                    if (!content.isEmpty()) {
                        currentState = SplitterState.INIT;
                    } else {
                        currentState = SplitterState.END;
                    }
                    yield new Chunk(suffix, Map.of());
                case END:
                    yield new Chunk(content, Map.of());
            };
        }

        private void breakdownContent() {
            assert currentState == SplitterState.INIT;
            assert content != null;
            // Find the index to open tag
            Matcher openTagMatcher = openTagPattern.matcher(content);
            if (!openTagMatcher.find()) {
                currentState = SplitterState.END;
                return;
            }
            int openTagIndex = openTagMatcher.start();
            prefix = content.substring(0, openTagIndex);

            currentState = SplitterState.PREFIX;

            // Find the index to close tag
            Matcher closeTagMatcher = closeTagPattern.matcher(content);
            closeTagMatcher.region(openTagMatcher.end(), content.length());
            if (!closeTagMatcher.find()) {
                throw new IndexOutOfBoundsException("Invalid HTML <%s> is not properly terminated".formatted(tagName));
            }
            
            // Extract complete tag including opening and closing tags
            tag = content.substring(openTagIndex, closeTagMatcher.end());

            content = content.substring(closeTagMatcher.end());

            // Find the index to the next opening tag
            Matcher nextOpenTagMatcher = openTagPattern.matcher(content);
            if (!nextOpenTagMatcher.find()) {
                // End of content. ie no rest
                suffix = content;
                content = "";
                return;
            }
            int nextOpenTagIndex = nextOpenTagMatcher.start();
            suffix = content.substring(0, nextOpenTagIndex);
            content = content.substring(nextOpenTagIndex);
        }
    }
}
