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
 * Unified wrapper for platform-specific ToolSpan implementations.
 */
public class UnifiedToolSpan {

    private final Object platformSpan;
    private final Class<?> platformSpanClass;

    public UnifiedToolSpan(String name) {
        try {
            if (!PlatformObservabilityManager.isAvailable()) {
                throw new RuntimeException("Platform-specific observability not available");
            }

            // Load the platform-specific ToolSpan class
            ClassLoader platformClassLoader = PlatformObservabilityManager.getPlatformClassLoader();
            platformSpanClass = platformClassLoader.loadClass("io.ballerina.stdlib.ai.observability.ToolSpan");
            Constructor<?> constructor = platformSpanClass.getConstructor(String.class);
            platformSpan = constructor.newInstance(name);
        } catch (Exception e) {
            throw new RuntimeException("Failed to create platform-specific ToolSpan", e);
        }
    }

    public void init(String tracer) {
        try {
            Method method = platformSpanClass.getMethod("init", String.class);
            method.invoke(platformSpan, tracer);
        } catch (Exception e) {
            throw new RuntimeException("Failed to init ToolSpan", e);
        }
    }

    public void enter() {
        try {
            Method method = platformSpanClass.getMethod("enter");
            method.invoke(platformSpan);
        } catch (Exception e) {
            throw new RuntimeException("Failed to enter ToolSpan", e);
        }
    }

    public void exit() {
        try {
            Method method = platformSpanClass.getMethod("exit");
            method.invoke(platformSpan);
        } catch (Exception e) {
            throw new RuntimeException("Failed to exit ToolSpan", e);
        }
    }

    public void setInput(String input) {
        try {
            Method method = platformSpanClass.getMethod("setInput", String.class);
            method.invoke(platformSpan, input);
        } catch (Exception e) {
            throw new RuntimeException("Failed to set input on ToolSpan", e);
        }
    }

    public void setOutput(String output) {
        try {
            Method method = platformSpanClass.getMethod("setOutput", String.class);
            method.invoke(platformSpan, output);
        } catch (Exception e) {
            throw new RuntimeException("Failed to set output on ToolSpan", e);
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
            throw new RuntimeException("Failed to set status on ToolSpan", e);
        }
    }

    private ClassLoader getCurrentPlatformClassLoader() {
        return PlatformObservabilityManager.getPlatformClassLoader();
    }
}