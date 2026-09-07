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

import ballerina/test;
import ballerina/ai;
import ballerina/http;

@test:Config {}
function testAgentChat() returns error? {
    ai:ChatClient chatClient = check new("http://localhost:9090/chatService");
    ai:ChatReqMessage req = {
        sessionId: "1",
        message: "Hello Ballerina!"
    };
    ai:ChatRespMessage resp = check chatClient->/chat.post(req);
    test:assertEquals(resp.message, "1: Hello Ballerina!", "Invalid response message");
}

@test:Config {}
function testAgentChatDecision() returns error? {
    ai:ChatClient chatClient = check new("http://localhost:9090/chatService");
    ai:DecisionMessage req = {
        sessionId: "1",
        decisions: {
            "req-1": {outcome: ai:APPROVE},
            "req-2": {outcome: ai:REJECT, reason: "not needed"}
        }
    };
    ai:ChatRespMessage resp = check chatClient->/decision.post(req);
    // Asserts the actual keys and values the resource received, not just how many arrived - a
    // swapped or dropped decision would still leave the map at length 2 but should fail this.
    string message = resp.message;
    test:assertTrue(message.includes("req-1=APPROVE"), "Missing or wrong decision for req-1: " + message);
    test:assertTrue(message.includes("req-2=REJECTnot needed"), "Missing or wrong decision for req-2: " + message);
}

// Verifies the dispatcher converts a returned `ai:ApprovalRequiredError` into a structured HTTP
// response (custom status + `{requests: [...]}` body), without the service doing any mapping.
// The fixture pauses with two pending requests, so this also verifies the dispatcher preserves
// a full batch rather than only the first entry.
@test:Config {}
function testAgentChatApprovalPause() returns error? {
    http:Client httpClient = check new ("http://localhost:9090");
    http:Response resp = check httpClient->/pausingService/chat.post({sessionId: "1", message: "refund order"});

    test:assertEquals(resp.statusCode, 403, "Expected the pause to map to HTTP 403");
    json body = check resp.getJsonPayload();
    json[] requests = check (check body.requests).ensureType();
    test:assertEquals(requests.length(), 2, "Expected two pending approval requests");
    test:assertEquals(check requests[0].toolName, "issueRefund", "Wrong tool name in first pending request");
    test:assertEquals(check requests[0].id, "req-1", "Wrong request id in first pending request");
    test:assertEquals(check requests[1].toolName, "cancelOrder", "Wrong tool name in second pending request");
    test:assertEquals(check requests[1].id, "req-2", "Wrong request id in second pending request");
}

// Verifies the dispatcher maps `ai:ApprovalNotFoundError` (a `Resume` sent for a session with
// nothing pending) to HTTP 404, with a structured body carrying both a stable `errorType`
// discriminator and a human-readable `message`.
@test:Config {}
function testAgentChatDecisionNoPending() returns error? {
    http:Client httpClient = check new ("http://localhost:9090");
    http:Response resp = check httpClient->/pausingService/decision.post({sessionId: "no-pending", decisions: {}});
    test:assertEquals(resp.statusCode, 404, "Expected ApprovalNotFoundError to map to HTTP 404");
    json body = check resp.getJsonPayload();
    test:assertEquals(check body.errorType, "ApprovalNotFoundError", "Wrong errorType in response body");
    string message = check (check body.message).ensureType();
    test:assertTrue(message.includes("No pending approval found"), "Expected message to explain why: " + message);
}

// Verifies the dispatcher maps `ai:UnknownApprovalIdError` (a `Resume` naming an id that isn't
// pending) to HTTP 400, with a structured body carrying both a stable `errorType`
// discriminator and a human-readable `message`.
@test:Config {}
function testAgentChatDecisionUnknownId() returns error? {
    http:Client httpClient = check new ("http://localhost:9090");
    http:Response resp = check httpClient->/pausingService/decision.post({sessionId: "1", decisions: {"bad-id": {outcome: ai:APPROVE}}});
    test:assertEquals(resp.statusCode, 400, "Expected UnknownApprovalIdError to map to HTTP 400");
    json body = check resp.getJsonPayload();
    test:assertEquals(check body.errorType, "UnknownApprovalIdError", "Wrong errorType in response body");
    string message = check (check body.message).ensureType();
    test:assertTrue(message.includes("Unknown approval id"), "Expected message to explain why: " + message);
}
