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

import ballerina/ai;
import ballerina/test;

@test:Config
function testAgentToolExecution() returns error? {
    string result = check agent.run("What is the sum of the following numbers 78 90 45 23 8?");
    test:assertEquals(result, "Answer is: 244");

    result = check agent.run("What is the product of 78 and 90?");
    test:assertEquals(result, "Answer is: 7020");

    result = check agent.run("Search for 'random'");
    test:assertEquals(result, "Answer is: No result found on doc for 'random'");

    result = check agent.run("List all mails");
    test:assertEquals(result, [{body: "Mail Body 1"}, {body: "Mail Body 2"}, {body: "Mail Body 3"}].toString());

    result = check agent.run("I'm John. Greet me once");
    test:assertEquals(result, "Hey John! Welcome to Ballerina!");
}

@test:Config
function testAgentToolExecutionWithContext() returns error? {
    string imageUrl = "https://ballerina.io/images/ballerina.png";
    ai:Context ctx = new;
    ctx.set("imageUrl", imageUrl);
    ctx.set("isImageSearchToolExecuted", false);

    string result = check agent.run("Search for a 'ballerina' image", context = ctx);
    test:assertEquals(result, string `Answer is: ${imageUrl}`);
    boolean isImageSearchToolExecuted = check ctx.getWithType("isImageSearchToolExecuted");
    test:assertTrue(isImageSearchToolExecuted);

    string videoUrl = "https://ballerina.io/video/ballerina.mp4";
    ctx.set("videoUrl", videoUrl);
    ctx.set("isVideoSearchToolExecuted", false);
    result = check agent.run("Search for a 'ballerina' video", context = ctx);
    boolean isVideoSearchToolExecuted = check ctx.getWithType("isVideoSearchToolExecuted");
    test:assertTrue(isVideoSearchToolExecuted);
    test:assertEquals(result, string `Answer is: ${videoUrl}`);
}

@test:Config {
    groups: ["mcp"]
}
function testAgentToolExecutionforMcpServer() returns error? {
    string result = check agent.run("I'm John. Greet me once");
    test:assertEquals(result, "Hey John! Welcome to Ballerina!");
}

isolated boolean toolLoadedDynamicaly = false;

@test:Config
function testAgentWithDynamicToolLoadingConfig() returns error? {
    string result = check dynamicToolLoadingAgent.run("What is the sum of the following numbers 78 90 45 23 8?");
    test:assertEquals(result, "Answer is: 244");
    lock {
        test:assertTrue(toolLoadedDynamicaly);
    }
}
