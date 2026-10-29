// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
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

import ballerina/ai.observe;
import ballerina/test;

// A span is the current AI span from its creation until it is closed, whether it succeeds or fails.
@test:Config {groups: ["tracing"]}
function testSpanIsCurrentUntilClosed() {
    observe:ChatSpan succeeded = observe:createChatSpan("test-model");
    test:assertTrue(observe:getCurrentAiSpan() === succeeded, "Expected the new span to be the current AI span");
    succeeded.close();
    test:assertTrue(observe:getCurrentAiSpan() is (), "Expected no current AI span after a successful close");

    observe:ChatSpan failed = observe:createChatSpan("test-model");
    test:assertTrue(observe:getCurrentAiSpan() === failed, "Expected the new span to be the current AI span");
    failed.close(error("LLM call failed"));
    test:assertTrue(observe:getCurrentAiSpan() is (), "Expected no current AI span after a failed close");
}
