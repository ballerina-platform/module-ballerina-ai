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

import java.util.Map;

public class HTMLHeaderSplitter extends AbstractTagSplitter {

    final String type;

    HTMLHeaderSplitter(int level) {
        super("h" + level);
        this.type = "h" + level;
    }

    @Override
    void onBreakdown(TagSplitterIterator iterator) {
        if (iterator.currentState != SplitterState.PREFIX) {
            return;
        }
        String tagContent = iterator.tag;
        // Extract content by removing HTML tags
        String cleanContent = tagContent.replaceAll("<[^>]*>", "").trim();
        Map<String, String> attributes = Map.of(type, cleanContent);

        iterator.suffixAttributes = attributes;
        iterator.tagAttributes = attributes;
    }
}
