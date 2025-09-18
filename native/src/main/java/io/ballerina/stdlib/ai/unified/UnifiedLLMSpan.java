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

package io.ballerina.stdlib.ai.unified;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;

/**
 * Unified wrapper for platform-specific LLMSpan implementations.
 */
public class UnifiedLLMSpan {

    private final Object platformSpan;
    private final Class<?> platformSpanClass;

    public UnifiedLLMSpan(String name, String model, String provider) {
        try {
            if (!PlatformObservabilityManager.isAvailable()) {
                throw new RuntimeException("Platform-specific observability not available");
            }

            // Load the platform-specific LLMSpan class
            ClassLoader platformClassLoader = PlatformObservabilityManager.getPlatformClassLoader();
            platformSpanClass = platformClassLoader.loadClass("io.ballerina.stdlib.ai.observability.LLMSpan");
            Constructor<?> constructor = platformSpanClass.getConstructor(String.class, String.class, String.class);
            platformSpan = constructor.newInstance(name, model, provider);
        } catch (Exception e) {
            throw new RuntimeException("Failed to create platform-specific LLMSpan", e);
        }
    }

    public void init(String tracer) {
        try {
            Method method = platformSpanClass.getMethod("init", String.class);
            method.invoke(platformSpan, tracer);
        } catch (Exception e) {
            throw new RuntimeException("Failed to init LLMSpan", e);
        }
    }

    public void enter() {
        try {
            Method method = platformSpanClass.getMethod("enter");
            method.invoke(platformSpan);
        } catch (Exception e) {
            throw new RuntimeException("Failed to enter LLMSpan", e);
        }
    }

    public void exit() {
        try {
            Method method = platformSpanClass.getMethod("exit");
            method.invoke(platformSpan);
        } catch (Exception e) {
            throw new RuntimeException("Failed to exit LLMSpan", e);
        }
    }

    public void setInput(String input) {
        try {
            Method method = platformSpanClass.getMethod("setInput", String.class);
            method.invoke(platformSpan, input);
        } catch (Exception e) {
            throw new RuntimeException("Failed to set input on LLMSpan", e);
        }
    }

    public void setOutput(String output) {
        try {
            Method method = platformSpanClass.getMethod("setOutput", String.class);
            method.invoke(platformSpan, output);
        } catch (Exception e) {
            throw new RuntimeException("Failed to set output on LLMSpan", e);
        }
    }

    public void setTokenCount(int totalTokens, int inputTokens, int outputTokens) {
        try {
            Method method = platformSpanClass.getMethod("setTokenCount", int.class, int.class, int.class);
            method.invoke(platformSpan, totalTokens, inputTokens, outputTokens);
        } catch (Exception e) {
            throw new RuntimeException("Failed to set token count on LLMSpan", e);
        }
    }

    public void addToolCallInputs(ToolRequest toolRequest) {
        try {
            // Load the platform-specific LLMSpan.ToolRequest class
            ClassLoader platformClassLoader = getCurrentPlatformClassLoader();
            Class<?> toolRequestClass = platformClassLoader.loadClass("io.ballerina.stdlib.ai.observability.LLMSpan$ToolRequest");
            Constructor<?> constructor = toolRequestClass.getConstructor(String.class, String.class, String.class);
            Object platformToolRequest = constructor.newInstance(toolRequest.name, toolRequest.input, toolRequest.id);

            // Get the method that takes varargs ToolRequest...
            Method method = null;
            for (Method m : platformSpanClass.getMethods()) {
                if ("addToolCallInputs".equals(m.getName()) && m.getParameterCount() == 1 &&
                    m.getParameterTypes()[0].isArray() &&
                    m.getParameterTypes()[0].getComponentType().equals(toolRequestClass)) {
                    method = m;
                    break;
                }
            }
            if (method == null) {
                throw new RuntimeException("Could not find addToolCallInputs method with ToolRequest[] parameter");
            }

            // Create an array with the single tool request
            Object toolRequestArray = java.lang.reflect.Array.newInstance(toolRequestClass, 1);
            java.lang.reflect.Array.set(toolRequestArray, 0, platformToolRequest);
            method.invoke(platformSpan, toolRequestArray);
        } catch (Exception e) {
            throw new RuntimeException("Failed to add tool call inputs on LLMSpan", e);
        }
    }

    public void addToolCallResponse(ToolResponse toolResponse) {
        try {
            // Load the platform-specific LLMSpan.ToolResponse class
            ClassLoader platformClassLoader = getCurrentPlatformClassLoader();
            Class<?> toolResponseClass = platformClassLoader.loadClass("io.ballerina.stdlib.ai.observability.LLMSpan$ToolResponse");
            Constructor<?> constructor = toolResponseClass.getConstructor(String.class, String.class, String.class);
            Object platformToolResponse = constructor.newInstance(toolResponse.name, toolResponse.output, toolResponse.id);

            Method method = platformSpanClass.getMethod("addToolCallResponse", toolResponseClass);
            method.invoke(platformSpan, platformToolResponse);
        } catch (Exception e) {
            throw new RuntimeException("Failed to add tool call response on LLMSpan", e);
        }
    }

    public void addIntermediateRequest(String request) {
        try {
            Method method = platformSpanClass.getMethod("addIntermediateRequest", String.class);
            method.invoke(platformSpan, request);
        } catch (Exception e) {
            throw new RuntimeException("Failed to add intermediate request on LLMSpan", e);
        }
    }

    public void addIntermediateResponse(String response) {
        try {
            Method method = platformSpanClass.getMethod("addIntermediateResponse", String.class);
            method.invoke(platformSpan, response);
        } catch (Exception e) {
            throw new RuntimeException("Failed to add intermediate response on LLMSpan", e);
        }
    }

    public void setStatus(SpanStatus status) {
        try {
            // Load the platform-specific Span.Status enum
            ClassLoader platformClassLoader = getCurrentPlatformClassLoader();
            Class<?> spanClass = platformClassLoader.loadClass("io.ballerina.stdlib.ai.observability.Span");
            Class<?> statusEnum = null;
            for (Class<?> innerClass : spanClass.getDeclaredClasses()) {
                if ("Status".equals(innerClass.getSimpleName())) {
                    statusEnum = innerClass;
                    break;
                }
            }

            if (statusEnum == null) {
                throw new RuntimeException("Could not find Span.Status enum");
            }

            Object statusValue = Enum.valueOf((Class<Enum>) statusEnum, status.name());
            Method method = platformSpanClass.getMethod("setStatus", statusEnum);
            method.invoke(platformSpan, statusValue);
        } catch (Exception e) {
            throw new RuntimeException("Failed to set status on LLMSpan", e);
        }
    }

    private ClassLoader getCurrentPlatformClassLoader() {
        return PlatformObservabilityManager.getPlatformClassLoader();
    }

    public static class ToolRequest {
        public final String name;
        public final String input;
        public final String id;

        public ToolRequest(String name, String input, String id) {
            this.name = name;
            this.input = input;
            this.id = id;
        }
    }

    public static class ToolResponse {
        public final String name;
        public final String output;
        public final String id;

        public ToolResponse(String name, String output, String id) {
            this.name = name;
            this.output = output;
            this.id = id;
        }
    }
}