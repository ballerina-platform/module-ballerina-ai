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

import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.types.ResourceMethodType;
import io.ballerina.runtime.api.types.ServiceType;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

import java.util.concurrent.CompletableFuture;

/**
 * Bridges the internal chat dispatcher service (attached to the underlying {@code http:Listener})
 * to the user's {@code ai:ChatService}. The dispatcher forwards each request here; this class
 * reflectively invokes the matching resource on the user's service so that a paused run
 * ({@code ai:ApprovalRequiredError}) is returned intact to the dispatcher, which maps it to an
 * HTTP response - the user's service never has to do that mapping itself.
 */
public final class NativeHttpToChatServiceAdaptor {

    // The user's ChatService, stored on the dispatcher as native data.
    private static final String USER_CHAT_SERVICE = "AI_USER_CHAT_SERVICE";
    // The dispatcher, stored on the user's ChatService as native data (used by `detach`).
    private static final String DISPATCHER = "AI_CHAT_DISPATCHER";
    private static final String POST_ACCESSOR = "post";

    private NativeHttpToChatServiceAdaptor() {
    }

    // Associates a dispatcher with the user's ChatService in both directions, so the dispatcher can
    // reach the user's resources and `detach` can recover the dispatcher from the user's service.
    public static void setChatService(BObject dispatcher, BObject chatService) {
        dispatcher.addNativeData(USER_CHAT_SERVICE, chatService);
        chatService.addNativeData(DISPATCHER, dispatcher);
    }

    // Returns the dispatcher previously associated with `chatService`, or null if none.
    public static Object getDispatcher(BObject chatService) {
        return chatService.getNativeData(DISPATCHER);
    }

    public static Object invokeChat(Environment env, BObject dispatcher, BMap<BString, Object> request) {
        return invokeResource(env, dispatcher, "chat", request);
    }

    public static Object invokeDecision(Environment env, BObject dispatcher, BMap<BString, Object> request) {
        return invokeResource(env, dispatcher, "decision", request);
    }

    private static ResourceMethodType findResource(BObject userService, String pathSegment) {
        ServiceType serviceType = (ServiceType) TypeUtils.getReferredType(TypeUtils.getType(userService));
        for (ResourceMethodType method : serviceType.getResourceMethods()) {
            String[] path = method.getResourcePath();
            if (POST_ACCESSOR.equalsIgnoreCase(method.getAccessor())
                    && path.length == 1 && pathSegment.equals(path[0])) {
                return method;
            }
        }
        return null;
    }

    private static Object invokeResource(Environment env, BObject dispatcher, String pathSegment, Object request) {
        BObject userService = (BObject) dispatcher.getNativeData(USER_CHAT_SERVICE);
        ResourceMethodType resource = findResource(userService, pathSegment);
        if (resource == null) {
            return ModuleUtils.createError("no 'post " + pathSegment + "' resource found in the attached chat service");
        }
        String methodName = resource.getName();
        return env.yieldAndRun(() -> {
            CompletableFuture<Object> future = new CompletableFuture<>();
            try {
                Object result = env.getRuntime().callMethod(userService, methodName, null, request);
                // A returned error (e.g. ApprovalRequiredError) comes back here as `result`, with its
                // type and detail intact, and flows through unchanged for the dispatcher to map.
                Utils.notifySuccess(future, result);
                return Utils.getResult(future);
            } catch (BError error) {
                // A panic from the user's resource; surface it as-is.
                return error;
            }
        });
    }
}
