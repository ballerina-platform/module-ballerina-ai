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

import java.io.PrintStream;

import org.graalvm.polyglot.Context;

public class PythonWrapper {

    private static final PrintStream out = System.out;

    private static class ContextHolder {

        private static final Context CONTEXT = createContext();

        private static Context createContext() {
            String pathToVenv = "/Users/heshanp/Projects/module-ballerina-ai/venvs/darwin";
            String sitePackagesPath = pathToVenv + "/lib/python3.11/site-packages";
            String stdLibPath = "/Users/heshanp/Projects/module-ballerina-ai/venvs/darwin-std-lib/python3.11";
            return Context.newBuilder("python")
                    .option("python.PythonHome", pathToVenv)
                    .option("python.PythonPath", sitePackagesPath + ":" + stdLibPath)
                    .option("python.StdLibHome", stdLibPath)
                    .option("python.ForceImportSite", "true")
                    .allowAllAccess(true)
                    .build();
        }
    }

    private static Context getContext() {
        return ContextHolder.CONTEXT;
    }

    public static synchronized void execVoid(String code) {
        String debugPy = System.getenv("DEBUG_PY");
        boolean isDebug = debugPy != null && !debugPy.isEmpty();
        try {
            getContext().eval("python", code);
            if (isDebug) {
                out.println("Executed Python code:\n" + code);
            }
        } catch (Exception e) {
            if (isDebug) {
                throw new RuntimeException("error executing: " + code, e);
            } else {
                throw new RuntimeException("unexpected error", e);
            }
        }
    }
}
