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
import io.ballerina.runtime.observability.ObserveUtils;
import io.ballerina.runtime.observability.ObserverContext;

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
    private static final String ENTRYPOINT_FUNCTION_MODULE_TAG = "entrypoint.function.module";
    private static final String ENTRYPOINT_SERVICE_NAME_TAG = "entrypoint.service.name";
    private static final String ENTRYPOINT_FUNCTION_NAME_TAG = "entrypoint.function.name";
    private static final String ENTRYPOINT_RESOURCE_ACCESSOR_TAG = "entrypoint.resource.accessor";

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

    public static Object invokeChat(Environment env, BObject dispatcher, BMap<BString, Object> request,
                                    BObject headers) {
        return invokeResource(env, dispatcher, "chat", request, headers);
    }

    public static Object invokeDecision(Environment env, BObject dispatcher, BMap<BString, Object> request,
                                        BObject headers) {
        return invokeResource(env, dispatcher, "decision", request, headers);
    }

    public static boolean hasResource(BObject dispatcher, BString path) {
        BObject userService = (BObject) dispatcher.getNativeData(USER_CHAT_SERVICE);
        return findResource(userService, path.getValue()) != null;
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

    private static Object invokeResource(Environment env, BObject dispatcher, String pathSegment,
                                         BMap<BString, Object> request, BObject headers) {
        BObject userService = (BObject) dispatcher.getNativeData(USER_CHAT_SERVICE);
        ResourceMethodType resource = findResource(userService, pathSegment);
        if (resource == null) {
            return ModuleUtils.createError("no 'post " + pathSegment + "' resource found in the attached chat service");
        }
        String methodName = resource.getName();

        int declared = resource.getParameters().length;
        if (declared > 2 || declared == 0) {
            return ModuleUtils.createError("the 'post " + pathSegment + "' resource declares " + declared
                    + " parameter(s). Only the payload, optionally followed by an 'http:Headers' parameter,"
                    + " is supported.");
        }
        Object[] args = declared == 2 ? new Object[]{request, headers} : new Object[]{request};
        ObserverContext dispatcherContext = ObserveUtils.isObservabilityEnabled()
                ? ObserveUtils.getObserverContextOfCurrentFrame(env) : null;
        ObserverContext userContext = dispatcherContext == null ? null : newUserContext(env, dispatcherContext);
        try {
            return env.yieldAndRun(() -> {
                CompletableFuture<Object> future = new CompletableFuture<>();
                try {
                    Object result = env.getRuntime().callMethod(userService, methodName, null, args);
                    // A returned error (e.g. ApprovalRequiredError) comes back here as `result`, with
                    // its type and detail intact, and flows through unchanged for the dispatcher to map.
                    Utils.notifySuccess(future, result);
                    return Utils.getResult(future);
                } catch (BError error) {
                    // A panic from the user's resource; surface it as-is.
                    return error;
                }
            });
        } finally {
            if (userContext != null) {
                restoreDispatcherContext(env, dispatcherContext, userContext);
            }
        }
    }

    // A trace's entrypoint (service, module, function and accessor) is taken from its first
    // resource, and every span beneath it inherits that. Here that is the dispatcher, an internal
    // service of this module, so the trace would name it instead of the user's service. To keep the
    // user's service the entrypoint, its resource is given a fresh context that is not yet started:
    // the runtime then fills the entrypoint from that resource, as it did before the dispatcher
    // existed, while the parent link keeps its span under the dispatcher's span.
    //
    // The context is seeded from the dispatcher's, and the resource overwrites these values when it
    // starts. Service resources are always instrumented, so it does start; but if it ever did not,
    // spans started under this context would otherwise find a null parent span and fail. Seeded,
    // they attach to the dispatcher's span as they would without this context.
    private static ObserverContext newUserContext(Environment env, ObserverContext dispatcherContext) {
        ObserverContext userContext = new ObserverContext();
        userContext.setParent(dispatcherContext);
        userContext.setSpan(dispatcherContext.getSpan());
        userContext.setServiceName(dispatcherContext.getServiceName());
        userContext.setEntrypointFunctionModule(dispatcherContext.getEntrypointFunctionModule());
        userContext.setEntrypointServiceName(dispatcherContext.getEntrypointServiceName());
        userContext.setEntrypointFunctionName(dispatcherContext.getEntrypointFunctionName());
        userContext.setEntrypointResourceAccessor(dispatcherContext.getEntrypointResourceAccessor());
        ObserveUtils.setObserverContextToCurrentFrame(env, userContext);
        return userContext;
    }

    // Puts the dispatcher's context back in place and gives it the entrypoint recorded by the user's
    // resource. Tags are copied onto a span only when it finishes, so the dispatcher's span reports
    // the user's service as well.
    private static void restoreDispatcherContext(Environment env, ObserverContext dispatcherContext,
                                                 ObserverContext userContext) {
        ObserveUtils.setObserverContextToCurrentFrame(env, dispatcherContext);
        if (!userContext.isStarted()) {
            // The user's resource was not observed, so there is no entrypoint to take from it.
            return;
        }
        dispatcherContext.setEntrypointFunctionModule(userContext.getEntrypointFunctionModule());
        dispatcherContext.setEntrypointServiceName(userContext.getEntrypointServiceName());
        dispatcherContext.setEntrypointFunctionName(userContext.getEntrypointFunctionName());
        dispatcherContext.setEntrypointResourceAccessor(userContext.getEntrypointResourceAccessor());
        addTagIfPresent(dispatcherContext, ENTRYPOINT_FUNCTION_MODULE_TAG, userContext.getEntrypointFunctionModule());
        addTagIfPresent(dispatcherContext, ENTRYPOINT_SERVICE_NAME_TAG, userContext.getEntrypointServiceName());
        addTagIfPresent(dispatcherContext, ENTRYPOINT_FUNCTION_NAME_TAG, userContext.getEntrypointFunctionName());
        addTagIfPresent(dispatcherContext, ENTRYPOINT_RESOURCE_ACCESSOR_TAG,
                userContext.getEntrypointResourceAccessor());
    }

    private static void addTagIfPresent(ObserverContext context, String key, String value) {
        if (value != null) {
            context.addTag(key, value);
        }
    }
}
