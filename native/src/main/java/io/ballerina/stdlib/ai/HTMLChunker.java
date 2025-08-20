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

import java.util.List;
import java.util.Set;

import io.ballerina.stdlib.ai.RecursiveChunker.Chunk;
import io.ballerina.stdlib.ai.RecursiveChunker.Splitter;

import static java.util.stream.IntStream.range;

public class HTMLChunker {

    static List<TextSegment> chunk(String content, int chunkSize, int maxOverlapSize) {
        List<Splitter> splitters = List.of(
                new HTMLHeaderSplitter(1),
                new HTMLHeaderSplitter(2),
                new HTMLHeaderSplitter(3),
                new HTMLHeaderSplitter(4),
                new HTMLHeaderSplitter(5),
                new HTMLHeaderSplitter(6),
                new HTMLParagraphSplitter(),
                // TODO: we need utility methods to create these
                new SimpleDelimiterSplitter("\\."),
                new SimpleDelimiterSplitter(" "),
                new SimpleDelimiterSplitter(""));
        RecursiveChunker chunker = new RecursiveChunker(Set.of());
        List<Chunk> chunks = chunker.chunkUsingSplitters(content, splitters, chunkSize, maxOverlapSize);
        return range(0, chunks.size())
                .mapToObj(i -> chunks.get(i).toTextSegment(i))
                .toList();
    }
}
