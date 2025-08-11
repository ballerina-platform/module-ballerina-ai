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

package io.ballerina.stdlib.ai;

import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BTypedesc;
import org.ballerinalang.langlib.value.EnsureType;

public final class Context {
    private static final BString CONTEXT_ENTRIES = StringUtils.fromString("entries");

    public static Object getWithType(BObject requestCtx, BString key, BTypedesc targetType) {
        BMap members = requestCtx.getMapValue(CONTEXT_ENTRIES);
        try {
            Object value = members.getOrThrow(key);
            Object convertedType = EnsureType.ensureType(value, targetType);
            if (convertedType instanceof BError) {
                return ModuleUtils.createError("type conversion failed for value of key: " + key.getValue());
            }
            return convertedType;
        } catch (RuntimeException e) {
            return ModuleUtils.createError("no member found for key: " + key.getValue());
        }
    }
}
