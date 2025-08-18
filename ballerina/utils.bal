// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
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

isolated function getToolParameterTypes(FunctionTool functionPointer) returns map<typedesc<anydata|Context>> {
    map<any> typedescriptors = getParameterTypes(functionPointer);
    map<typedesc<anydata|Context>> allowedInputTypes = {};
    foreach [string, any] [parmeterName, typedescriptor] in typedescriptors.entries() {
        if typedescriptor is typedesc<anydata|Context> {
            allowedInputTypes[parmeterName] = typedescriptor;
        }
    }
    return allowedInputTypes;
}

isolated function getParameterTypes(FunctionTool functionPointer) returns map<any> = @java:Method {
    'class: "io.ballerina.stdlib.ai.Utils"
} external;

isolated function isMapType(typedesc<anydata> typedescVal) returns boolean = @java:Method {
    'class: "io.ballerina.stdlib.ai.Utils"
} external;

isolated function isContextType(typedesc<anydata|Context> targetTypedesc, typedesc<Context> contextTypedesc = Context)
returns boolean = @java:Method {
    'class: "io.ballerina.stdlib.ai.Utils"
} external;

isolated function getFunctionName(FunctionTool toolFunction) returns string = @java:Method {
    'class: "io.ballerina.stdlib.ai.Utils"
} external;

isolated function getArgsWithDefaultsExcludingContext(FunctionTool toolFunction, map<anydata> value)
returns map<anydata> = @java:Method {
    'class: "io.ballerina.stdlib.ai.Utils"
} external;

isolated function invokeOnChatMessageFunction(any event, string eventFunction, service object {} serviceObj)
    returns ChatRespMessage|error = @java:Method {
    'class: "io.ballerina.stdlib.ai.NativeHttpToChatServiceAdaptor"
} external;

isolated function getChatMessageStringContent(Prompt|string prompt) returns string {
    if prompt is string {
        return prompt;
    }
    string str = prompt.strings[0];
    anydata[] insertions = prompt.insertions;
    foreach int i in 0 ..< insertions.length() {
        anydata value = insertions[i];
        string promptStr = prompt.strings[i + 1];
        if value is TextDocument|TextChunk {
            str = str + value.content + promptStr;
            continue;
        }
        str = str + value.toString() + promptStr;
    }
    return str.trim();
}

isolated function getRetryConfigValues(GeneratorConfig generatorConfig) returns [int, decimal] {
    ProviderRetryConfig? retryConfig = generatorConfig.retryConfig;
    if retryConfig != () {
        int count = retryConfig.count;
        if count > 0 {
            return [count, retryConfig.interval];
        }
    }
    return [0, 0d];
}
