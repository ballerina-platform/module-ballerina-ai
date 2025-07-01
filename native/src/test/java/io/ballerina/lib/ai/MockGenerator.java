/*
 * Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.lib.ai;

import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.types.TypeTags;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BTypedesc;

/*
 * Mock generator for model providers inside tests.
 */
public class MockGenerator {
    public static Object generate(BObject prompt, BTypedesc expectedType) {
        Type type = expectedType.getDescribingType();
        return switch (type.getTag()) {
            case TypeTags.STRING_TAG -> "2";
            case TypeTags.INT_TAG -> 2;
            case TypeTags.FLOAT_TAG -> 2f;
            case TypeTags.BOOLEAN_TAG -> true;
            default -> throw new RuntimeException("Unsupported type: " + type.getName() +
                    ". Supported types are: string, int, float, boolean for Mock LLM test.");
        };
    }
}
