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

import io.ballerina.projects.plugins.CompilerLifecycleContext;
import io.ballerina.projects.plugins.CompilerLifecycleListener;

import java.util.List;

/**
 * Registers the endpoint metadata task to run after code generation has completed.
 */
public class AiCompilerLifecycleListener extends CompilerLifecycleListener {

    private final List<Endpoint> endpoints;

    AiCompilerLifecycleListener(List<Endpoint> endpoints) {
        this.endpoints = endpoints;
    }

    @Override
    public void init(CompilerLifecycleContext context) {
        context.addCodeGenerationCompletedTask(new EndpointMetadataTask(endpoints));
    }
}
