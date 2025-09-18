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
 * Unified wrapper for platform-specific AgentSpan implementations.
 */
public class UnifiedAgentSpan {

    private final Object platformSpan;
    private final Class<?> platformSpanClass;

    public UnifiedAgentSpan(String name) {
        try {
            if (!PlatformObservabilityManager.isAvailable()) {
                throw new RuntimeException("Platform-specific observability not available");
            }

            // Load the platform-specific AgentSpan class using the platform class loader from PlatformObservabilityManager
            ClassLoader platformClassLoader = PlatformObservabilityManager.getPlatformClassLoader();
            platformSpanClass = platformClassLoader.loadClass("io.ballerina.stdlib.ai.observability.AgentSpan");
            Constructor<?> constructor = platformSpanClass.getConstructor(String.class);
            platformSpan = constructor.newInstance(name);
        } catch (Exception e) {
            throw new RuntimeException("Failed to create platform-specific AgentSpan", e);
        }
    }

    public void init(String tracer) {
        try {
            Method method = platformSpanClass.getMethod("init", String.class);
            method.invoke(platformSpan, tracer);
        } catch (Exception e) {
            throw new RuntimeException("Failed to init AgentSpan", e);
        }
    }

    public void enter() {
        try {
            Method method = platformSpanClass.getMethod("enter");
            method.invoke(platformSpan);
        } catch (Exception e) {
            throw new RuntimeException("Failed to enter AgentSpan", e);
        }
    }

    public void exit() {
        try {
            Method method = platformSpanClass.getMethod("exit");
            method.invoke(platformSpan);
        } catch (Exception e) {
            throw new RuntimeException("Failed to exit AgentSpan", e);
        }
    }

    public void setInput(String input) {
        try {
            Method method = platformSpanClass.getMethod("setInput", String.class);
            method.invoke(platformSpan, input);
        } catch (Exception e) {
            throw new RuntimeException("Failed to set input on AgentSpan", e);
        }
    }

    public void setOutput(String output) {
        try {
            Method method = platformSpanClass.getMethod("setOutput", String.class);
            method.invoke(platformSpan, output);
        } catch (Exception e) {
            throw new RuntimeException("Failed to set output on AgentSpan", e);
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
            throw new RuntimeException("Failed to set status on AgentSpan", e);
        }
    }

    private ClassLoader getCurrentPlatformClassLoader() {
        return PlatformObservabilityManager.getPlatformClassLoader();
    }

}