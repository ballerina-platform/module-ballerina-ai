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

import ballerina/ai;
import ballerina/http;
import ballerina/lang.runtime;
import ballerina/observe.mockextension as mock;
import ballerina/test;

// Tracing names a service by its attach point, so the user's service is traced as `/tracedChatService`.
const TRACED_SERVICE_NAME = "/tracedChatService";
// The internal service `ai:Listener` attaches in place of the user's one. It is a service class with
// no attach point of its own, so tracing names it `<org>_<module>_svc_<index>`.
const DISPATCHER_SERVICE_NAME = "ballerina_ai_svc_0";
const ENTRYPOINT_SERVICE_NAME = "entrypoint.service.name";
const ENTRYPOINT_FUNCTION_MODULE = "entrypoint.function.module";

final ai:Agent tracedChatAgent = check new (model = model,
    systemPrompt = {role: "Greeter", instructions: "Greet the user."}, tools = []);

// Used only by the test below, so the spans it produces are not mixed with those of other tests.
service /tracedChatService on chatListener {
    resource function post chat(@http:Payload ai:ChatReqMessage request, http:Headers headers)
            returns ai:ChatRespMessage|error {
        return {message: check tracedChatAgent.run(request.message, request.sessionId)};
    }
}

// A trace's entrypoint is the first resource it passes through, which for a chat request is the
// dispatcher inside `ai:Listener`. The trace must still name the user's service and module as its
// entrypoint, as tooling uses `entrypoint.service.name` to tell apart the same agent running in
// different services. This holds for the dispatcher's span and every span beneath it.
//
// In the `tracing` group, which the GraalVM check disables: the mock tracer converts its spans to JSON
// reflectively, and its span classes are not registered for reflection in a native image.
@test:Config {groups: ["tracing"]}
function testChatServiceIsTraceEntrypoint() returns error? {
    ai:ChatClient chatClient = check new ("http://localhost:9090/tracedChatService");
    _ = check chatClient->/chat.post({sessionId: "1", message: "Greet John"});

    mock:Span[] userSpans = mock:getFinishedSpans(TRACED_SERVICE_NAME);
    mock:Span[] resourceSpans = userSpans.filter(span => span.operationName == "post /chat");
    test:assertEquals(resourceSpans.length(), 1, "Expected a single span for the chat resource");
    mock:Span resourceSpan = resourceSpans[0];
    string userModule = resourceSpan.tags.get("src.module");

    mock:Span[] traceSpans = userSpans.filter(span => span.traceId == resourceSpan.traceId);
    test:assertTrue(traceSpans.some(span => span.operationName.startsWith("invoke_agent")),
            "Expected the agent run to be traced beneath the chat resource");
    traceSpans.push(check waitForDispatcherSpan(resourceSpan.parentId));
    foreach mock:Span span in traceSpans {
        test:assertEquals(span.tags[ENTRYPOINT_SERVICE_NAME], TRACED_SERVICE_NAME,
                string `Wrong entrypoint service name on span '${span.operationName}'`);
        test:assertEquals(span.tags[ENTRYPOINT_FUNCTION_MODULE], userModule,
                string `Wrong entrypoint module on span '${span.operationName}'`);
    }
}

// The dispatcher's span is the parent of the user resource's span. It may finish only after the
// response has reached the client, so it is polled for briefly.
function waitForDispatcherSpan(string spanId) returns mock:Span|error {
    foreach int _ in 0 ..< 50 {
        mock:Span[] spans = mock:getFinishedSpans(DISPATCHER_SERVICE_NAME).filter(span => span.spanId == spanId);
        if spans.length() > 0 {
            return spans[0];
        }
        runtime:sleep(0.1);
    }
    return error("The dispatcher's span did not finish");
}
