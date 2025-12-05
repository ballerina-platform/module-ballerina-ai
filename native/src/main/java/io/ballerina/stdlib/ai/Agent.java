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

import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.types.PredefinedTypes;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BTypedesc;

public class Agent {
    public static final String RUN_INTERNAL_METHOD_NAME = "runInternal";

    private Agent() {
    }

    @SuppressWarnings("unused")
    public static Object run(Environment env, BObject agent,
                             BString query, BString sessionId, BObject context, BTypedesc td) {
        return env.yieldAndRun(() -> {
            try {
                Object[] paramFeed = getRunInternalMethodParams(query, sessionId, context, td);
                return env.getRuntime().callMethod(agent, RUN_INTERNAL_METHOD_NAME, null, paramFeed);
            } catch (BError bError) {
                return ModuleUtils.createError("Unable to obtain valid answer from the agent", bError);
            }
        });
    }

    private static Object[] getRunInternalMethodParams(BString query, BString sessionId, BObject context,
                                                       BTypedesc td) {
        boolean withTrace = !TypeUtils.isSameType(PredefinedTypes.TYPE_STRING, td.getDescribingType());
        return new Object[]{
                query, sessionId, context, withTrace
        };
    }
}
