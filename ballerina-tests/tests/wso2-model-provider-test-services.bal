// Copyright (c) 2025 WSO2 LLC. (http://www.wso2.org).
//
// WSO2 Inc. licenses this file to you under the Apache License,
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

import ballerina/http;
import ballerina/test;

service /llm on new http:Listener(8080) {
    resource function post azureopenai/deployments/gpt4onew/chat/completions(
            CreateChatCompletionRequest payload) returns CreateChatCompletionResponse|error {
        test:assertEquals(payload?.temperature, 0.7d);
        ChatCompletionRequestMessage[] messages = check payload.messages.ensureType();
        ChatCompletionRequestMessage message = messages[0];

        json[]? content = check message["content"].ensureType();
        if content is () {
            test:assertFail("Expected content in the payload");
        }

        string initialContent = (check content[0].text).toString();
        test:assertEquals(content, getExpectedContentParts(initialContent),
                string `Test failed for prompt:- ${initialContent}`);
        test:assertEquals(message.role, "user");
        ChatCompletionTool[]? tools = payload.tools;
        if tools is () || tools.length() == 0 {
            test:assertFail("No tools in the payload");
        }

        map<json>? parameters = check tools[0].'function?.parameters.toJson().cloneWithType();
        if parameters is () {
            test:assertFail("No parameters in the expected tool");
        }

        test:assertEquals(parameters, getExpectedParameterSchema(initialContent),
                string `Test failed for prompt:- ${initialContent}`);
        return getTestServiceResponse(initialContent);
    }
}
