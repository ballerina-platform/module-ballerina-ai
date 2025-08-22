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

import dev.langchain4j.data.segment.TextSegment;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import static java.util.stream.IntStream.range;

public class HtmlChunker {

    enum HtmlChunkStrategy {
        HTML_HEADER, HTML_PARAGRAPH, HTML_LINE, SENTENCE, WORD, CHARACTER;

        public List<RecursiveChunker.Splitter> getSplitters() {
            List<RecursiveChunker.Splitter> splitters = new ArrayList<>();

            switch (this) {
                case HTML_HEADER:
                    splitters.addAll(List.of(
                            new HtmlHeaderSplitter(1),
                            new HtmlHeaderSplitter(2),
                            new HtmlHeaderSplitter(3),
                            new HtmlHeaderSplitter(4),
                            new HtmlHeaderSplitter(5),
                            new HtmlHeaderSplitter(6)));
                    // fall through
                case HTML_PARAGRAPH:
                    splitters.add(new HtmlParagraphSplitter());
                    // fall through
                case HTML_LINE:
                    splitters.add(new RecursiveChunker.SimpleDelimiterSplitter("<br>"));
                    // fall through
                case SENTENCE:
                    splitters.add(RecursiveChunker.Splitter.createSentenceSplitter());
                    // fall through
                case WORD:
                    splitters.add(RecursiveChunker.Splitter.createWordSplitter());
                    // fall through
                case CHARACTER:
                    splitters.add(RecursiveChunker.Splitter.createCharacterSplitter());
            }

            return splitters;
        }
    }

    static List<TextSegment> chunk(String content, HtmlChunkStrategy strategy, int maxChunkSize, int maxOverlapSize) {
        if (maxChunkSize <= 0) {
            throw new IllegalArgumentException("Chunk size must be greater than 0");
        }
        if (maxOverlapSize > maxChunkSize) {
            throw new IllegalArgumentException("Max overlap size must be less than or equal to chunk size");
        }
        RecursiveChunker chunker = new RecursiveChunker(Set.of());
        List<RecursiveChunker.Chunk> chunks =
                chunker.chunkUsingSplitters(content, strategy.getSplitters(), maxChunkSize, maxOverlapSize);
        return range(0, chunks.size())
                .mapToObj(i -> chunks.get(i).toTextSegment(i))
                .toList();
    }

    static List<TextSegment> chunk(String content, int chunkSize, int maxOverlapSize) {
        RecursiveChunker chunker = new RecursiveChunker(Set.of());
        List<RecursiveChunker.Chunk> chunks =
                chunker.chunkUsingSplitters(content, HtmlChunkStrategy.HTML_HEADER.getSplitters(), chunkSize,
                        maxOverlapSize);
        return range(0, chunks.size())
                .mapToObj(i -> chunks.get(i).toTextSegment(i))
                .toList();
    }
}
