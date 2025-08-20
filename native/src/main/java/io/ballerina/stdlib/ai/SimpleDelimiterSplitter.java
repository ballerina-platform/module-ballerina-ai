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
import java.util.regex.Matcher;
import java.util.regex.Pattern;

class SimpleDelimiterSplitter implements RecursiveChunker.Splitter {

    private final Pattern pattern;

    SimpleDelimiterSplitter(String delimiter) {
        pattern = Pattern.compile(Pattern.quote(delimiter));
    }

    @Override
    public Iterator<RecursiveChunker.Chunk> split(String content) {
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
            public RecursiveChunker.Chunk next() {
                if (!hasNext()) {
                    throw new java.util.NoSuchElementException();
                }
                hasNextPiece = false;

                return new RecursiveChunker.Chunk(nextPiece, Map.of());
            }
        };
    }
}
