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

// Associates the internal dispatcher with the user's `ChatService` (both directions), so the
// dispatcher can invoke the user's resources and `Listener.detach` can recover the dispatcher.
isolated function setChatService(ChatDispatcherService dispatcher, ChatService chatService) = @java:Method {
    'class: "io.ballerina.stdlib.ai.NativeHttpToChatServiceAdaptor"
} external;

// Recovers the dispatcher previously associated with `chatService`, or `()` if none.
isolated function getDispatcher(ChatService chatService) returns ChatDispatcherService? = @java:Method {
    'class: "io.ballerina.stdlib.ai.NativeHttpToChatServiceAdaptor"
} external;

// Reflectively invokes the user service's `post chat` resource, returning its result (a
// `ChatRespMessage`, or an `error` such as `ApprovalRequiredError`) intact.
isolated function invokeChat(ChatDispatcherService dispatcher, ChatReqMessage request)
    returns ChatRespMessage|error = @java:Method {
    'class: "io.ballerina.stdlib.ai.NativeHttpToChatServiceAdaptor"
} external;

// Reflectively invokes the user service's `post decision` resource, returning its result intact.
isolated function invokeDecision(ChatDispatcherService dispatcher, DecisionMessage request)
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

isolated function entryMatchesFilters(VectorMatch|InMemoryVectorEntry entry,
        MetadataFilters filters) returns boolean|Error {
    Metadata? metadata = entry.chunk.metadata;
    if metadata is () {
        return false;
    }
    return evaluateFilterNode(metadata, filters);
}

isolated function evaluateFilterNode(Metadata content, MetadataFilters|MetadataFilter node) returns boolean|Error {
    if node is MetadataFilter {
        boolean|error result = content.hasKey(node.key) ? compareValues(content.get(node.key), node.operator, node.value) : false;
        return result is error ? error(result.message(), result.cause()) : result;
    }
    boolean[] results = from MetadataFilters|MetadataFilter child in node.filters
        select check evaluateFilterNode(content, child);
    return evaluateCondition(node.condition, results);
}

isolated function evaluateCondition(MetadataFilterCondition condition, boolean[] results) returns boolean {
    if condition == AND {
        return !results.some(result => result == false);
    }
    return results.some(result => result == true);
}

isolated function compareValues(json left, MetadataFilterOperator operation, json right) returns boolean|error {
    match operation {
        EQUAL => {
            return left == right;
        }
        NOT_EQUAL => {
            return left != right;
        }
        IN => {
            if right is json[] {
                foreach json value in right {
                    if left == value {
                        return true;
                    }
                }
            }
            return false;
        }
        NOT_IN => {
            if right is json[] {
                foreach json value in right {
                    if left == value {
                        return false;
                    }
                }
                return true;
            }
            return false;
        }
        GREATER_THAN => {
            return check left.cloneWithType(decimal) > check right.cloneWithType(decimal);
        }
        LESS_THAN => {
            return check left.cloneWithType(decimal) < check right.cloneWithType(decimal);
        }
        GREATER_THAN_OR_EQUAL => {
            return check left.cloneWithType(decimal) >= check right.cloneWithType(decimal);
        }
        LESS_THAN_OR_EQUAL => {
            return check left.cloneWithType(decimal) <= check right.cloneWithType(decimal);
        }
        _ => {
            return error(string `Unsupported operator: ${operation}`);
        }
    }
}

isolated function getRetryConfigValues(GeneratorConfig generatorConfig) returns [int, decimal]|Error {
    RetryConfig? retryConfig = generatorConfig.retryConfig;
    if retryConfig != () {
        int count = retryConfig.count;
        decimal? interval = retryConfig.interval;

        if count < 0 {
            return error("Invalid retry count: " + count.toString());
        }
        if interval < 0d {
            return error("Invalid retry interval: " + interval.toString());
        }

        return [count, interval ?: 0d];
    }
    return [0, 0d];
}
