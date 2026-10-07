/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
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

package io.ballerina.stdlib.ai.plugin;

import io.ballerina.projects.plugins.CompilerLifecycleEventContext;
import io.ballerina.projects.plugins.CompilerLifecycleTask;
import io.ballerina.stdlib.ai.plugin.diagnostics.CompilationDiagnostic;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.List;

import static io.ballerina.stdlib.ai.plugin.OpenAPIGenerator.NullLocation;

/**
 * Publishes every endpoint collected by {@link EndpointExportTask} during code analysis to Ballerina lang, once for
 * the whole compilation after code generation has completed.
 */
public class EndpointMetadataTask implements CompilerLifecycleTask<CompilerLifecycleEventContext> {
    private static final String ENDPOINT_META_INFO_CLASS = "io.ballerina.projects.plugins.EndpointMetaInfo";
    private static final String ADD_ENDPOINT_METADATA_METHOD = "addEndpointMetadata";

    private final List<Endpoint> endpoints;

    EndpointMetadataTask(List<Endpoint> endpoints) {
        this.endpoints = endpoints;
    }

    @Override
    public void perform(CompilerLifecycleEventContext context) {
        if (context.compilation().diagnosticResult().hasErrors() || endpoints.isEmpty()) {
            return;
        }
        try {
            for (Endpoint endpoint : endpoints) {
                addEndpointMetadata(context, endpoint);
            }
        } catch (ReflectiveOperationException | SecurityException e) {
            context.reportDiagnostic(CompilationDiagnostic.getDiagnostic(
                    CompilationDiagnostic.UNSUPPORTED_ENDPOINT_METADATA, new NullLocation()));
        }
    }

    // The endpoint metadata API is only available from Ballerina 2201.13.6 onwards, hence it is invoked reflectively
    private void addEndpointMetadata(CompilerLifecycleEventContext context, Endpoint endpoint)
            throws ReflectiveOperationException {
        Class<?> endpointMetaInfoClass = Class.forName(ENDPOINT_META_INFO_CLASS);
        Constructor<?> constructor = endpointMetaInfoClass.getConstructor(String.class, int.class, String.class,
                String.class, String.class);
        Object endpointMetaInfo = constructor.newInstance(endpoint.name(), endpoint.port(), endpoint.basePath(),
                endpoint.type(), endpoint.schemaPath());
        Method method = context.getClass().getMethod(ADD_ENDPOINT_METADATA_METHOD, endpointMetaInfoClass);
        method.setAccessible(true);
        method.invoke(context, endpointMetaInfo);
    }
}
