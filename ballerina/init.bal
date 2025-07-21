// Copyright (c) 2025 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/jballerina.java;

# Configurable for WSO2 provider.
configurable Wso2ProviderConfig? wso2ProviderConfig = ();

isolated function init() returns Error? {
    lock {
        Wso2ProviderConfig? config = wso2ProviderConfig;
        if config is () {
            defaultModelProvider = ();
            defaultEmbeddingProvider = ();
        } else {
            defaultModelProvider = check new Wso2ModelProvider(config.serviceUrl, config.accessToken);
            defaultEmbeddingProvider = check new Wso2EmbeddingProvider(config.serviceUrl, config.accessToken);
        }
    }

    setModule();
}

isolated function setModule() = @java:Method {
    'class: "io.ballerina.stdlib.ai.ModuleUtils"
} external;
