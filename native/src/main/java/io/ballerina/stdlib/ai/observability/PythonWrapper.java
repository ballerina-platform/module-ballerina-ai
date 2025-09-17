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

package io.ballerina.stdlib.ai.observability;

import org.graalvm.polyglot.Context;
import org.graalvm.python.embedding.GraalPyResources;

public class PythonWrapper {

    private static class ContextHolder {

        static final Context context = GraalPyResources.createContext();
    }

    private static Context getContext() {
        return ContextHolder.context;
    }

    public static synchronized void execVoid(String code) {
        try {
            getContext().eval("python", code);
        } catch (Exception e) {
            String debugPy = System.getenv("DEBUG_PY");
            if (debugPy != null && !debugPy.isEmpty()) {
                throw new RuntimeException("error executing: " + code, e);
            } else {
                throw new RuntimeException("unexpected error", e);
            }
        }
    }
}
