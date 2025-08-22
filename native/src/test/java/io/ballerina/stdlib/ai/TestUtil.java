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

import java.lang.reflect.Field;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.Collectors;

public class TestUtil {

    public static void resetChunkIdCounter() throws Exception {
        Field nextIdField = RecursiveChunker.Chunk.class.getDeclaredField("nextId");
        nextIdField.setAccessible(true);
        AtomicLong nextId = (AtomicLong) nextIdField.get(null);
        nextId.set(0);
    }

    static String formatChunksOutput(List<TextSegment> chunks, int chunkSize, int maxOverlapSize) {
        StringBuilder sb = new StringBuilder();
        sb.append(chunkSize).append(" ").append(maxOverlapSize).append("\n\n");

        for (int i = 0; i < chunks.size(); i++) {
            sb.append("--- Chunk ").append(i + 1).append(" ---\n");

            // Add metadata if present
            Map<String, Object> metadata = chunks.get(i).metadata().toMap();
            String body = metadata.keySet().stream().sorted().map(key -> """
                            "%s": "%s"
                            """.formatted(key, metadata.get(key).toString())).map(String::trim)
                    .collect(Collectors.joining(","));
            sb.append("Metadata: {").append(body).append("}\n");

            sb.append(chunks.get(i).text());
            if (i < chunks.size() - 1) {
                sb.append("\n\n");
            }
        }

        return sb.toString();
    }
}
