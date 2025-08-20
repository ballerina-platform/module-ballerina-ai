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

import io.ballerina.stdlib.ai.RecursiveChunker.Chunk;
import io.ballerina.stdlib.ai.RecursiveChunker.Splitter;

import static java.util.stream.IntStream.range;

public class HTMLChunker {

    enum HTMLChunkStrategy {
        HTML_HEADER, HTML_PARAGRAPH, HTML_LINE, SENTENCE, WORD, CHARACTER;

        public List<Splitter> getSplitters() {
            List<Splitter> splitters = new ArrayList<>();

            switch (this) {
                case HTML_HEADER:
                    splitters.addAll(List.of(
                            new HTMLHeaderSplitter(1),
                            new HTMLHeaderSplitter(2),
                            new HTMLHeaderSplitter(3),
                            new HTMLHeaderSplitter(4),
                            new HTMLHeaderSplitter(5),
                            new HTMLHeaderSplitter(6)));
                case HTML_PARAGRAPH:
                    splitters.add(new HTMLParagraphSplitter());
                case HTML_LINE:
                    splitters.add(new RecursiveChunker.SimpleDelimiterSplitter("<br>"));
                case SENTENCE:
                    splitters.add(Splitter.createSentenceSplitter());
                case WORD:
                    splitters.add(Splitter.createWordSplitter());
                case CHARACTER:
                    splitters.add(Splitter.createCharacterSplitter());
            }

            return splitters;
        }
    }

    static List<TextSegment> chunk(String content, HTMLChunkStrategy strategy, int maxChunkSize, int maxOverlapSize) {
        if (maxChunkSize <= 0) {
            throw new IllegalArgumentException("Chunk size must be greater than 0");
        }
        if (maxOverlapSize > maxChunkSize) {
            throw new IllegalArgumentException("Max overlap size must be less than or equal to chunk size");
        }
        RecursiveChunker chunker = new RecursiveChunker(Set.of());
        List<Chunk> chunks =
                chunker.chunkUsingSplitters(content, strategy.getSplitters(), maxChunkSize, maxOverlapSize);
        return range(0, chunks.size())
                .mapToObj(i -> chunks.get(i).toTextSegment(i))
                .toList();
    }

    static List<TextSegment> chunk(String content, int chunkSize, int maxOverlapSize) {
        RecursiveChunker chunker = new RecursiveChunker(Set.of());
        List<Chunk> chunks =
                chunker.chunkUsingSplitters(content, HTMLChunkStrategy.HTML_HEADER.getSplitters(), chunkSize,
                        maxOverlapSize);
        return range(0, chunks.size())
                .mapToObj(i -> chunks.get(i).toTextSegment(i))
                .toList();
    }
}
