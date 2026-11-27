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

import ballerina/a2a;
import ballerina/http;
import ballerina/test;

// A bare HTTP+JSON agent that misbehaves on request, for what a real agent cannot be made to do: refuse to cancel a
// task, reject a conversation id, and finish a task between two reads of it. The card says it cannot stream, so every
// request is one blocking call.

const int A2A_FAULT_TEST_PORT = 19304;
final string a2aFaultUrl = string `http://localhost:${A2A_FAULT_TEST_PORT}`;

listener http:Listener a2aFaultListener = new (A2A_FAULT_TEST_PORT);

// How many times each task was read, to finish "race" tasks on their second read.
isolated map<int> a2aFaultReads = {};
isolated int a2aFaultTasks = 0;

isolated function a2aFaultTaskJson(string id, string state, string? text = ()) returns json {
    map<json> task = {id, contextId: "fault-context", status: {state}};
    if text is string {
        task["artifacts"] = [{artifactId: "result", parts: [{text}]}];
    }
    return task;
}

isolated function a2aFaultError(int statusCode, string status, string reason, string message) returns http:Response {
    http:Response response = new;
    response.statusCode = statusCode;
    response.setJsonPayload({
        "error": {
            "code": statusCode,
            "status": status,
            "message": message,
            "details": [{"@type": "type.googleapis.com/google.rpc.ErrorInfo", "reason": reason, "domain": "a2a-protocol.org"}]
        }
    });
    return response;
}

service / on a2aFaultListener {
    resource function post message\:send(@http:Payload json body) returns http:Response|json|error {
        json message = check body.message;
        json|error contextId = message.contextId;
        if contextId is string && contextId == "gone-context" {
            return a2aFaultError(404, "NOT_FOUND", "TASK_NOT_FOUND", "no such conversation");
        }
        json[] parts = <json[]>check message.parts;
        string text = (check parts[0].text).toString();
        if text == "running" || text == "race" {
            int n = 0;
            lock {
                a2aFaultTasks += 1;
                n = a2aFaultTasks;
            }
            return {task: a2aFaultTaskJson(string `${text}-${n}`, "TASK_STATE_WORKING")};
        }
        return {message: {messageId: "fault-direct", role: "ROLE_AGENT", parts: [{text: "direct reply"}]}};
    }

    resource function get tasks/[string id]() returns json {
        int reads = 0;
        lock {
            reads = (a2aFaultReads[id] ?: 0) + 1;
            a2aFaultReads[id] = reads;
        }
        if id.startsWith("race-") && reads >= 2 {
            return a2aFaultTaskJson(id, "TASK_STATE_COMPLETED", "race done");
        }
        return a2aFaultTaskJson(id, "TASK_STATE_WORKING");
    }

    // `tasks/{id}:cancel`: this agent never cancels.
    resource function post tasks/[string idAndAction]() returns http:Response {
        return a2aFaultError(409, "FAILED_PRECONDITION", "TASK_NOT_CANCELABLE", "this agent cannot cancel");
    }
}

isolated function a2aFaultCard() returns a2a:AgentCard {
    a2a:AgentCard card = a2aCard("Faulty Agent", interfaces = [
        {url: a2aFaultUrl, protocolBinding: "HTTP+JSON", protocolVersion: "1.0"}
    ]);
    card.capabilities.streaming = false;
    return card;
}

@test:Config {groups: ["a2a"]}
function testA2aAskSaysWhenTheAgentDidNotConfirmTheCancellation() returns error? {
    A2aToolKit toolkit = check new (a2aFaultCard(), clientConfig = {timeout: 1});
    test:assertTrue((check a2aAsk(toolkit, "running", "no-cancel")).startsWith("[WORKING]"));
    foreach int _ in 2 ... A2A_MAX_STALLED_REPLIES {
        string again = check a2aAsk(toolkit, "anything new?", "no-cancel");
        test:assertTrue(again.startsWith("[WORKING]"), again);
    }
    string moved = check a2aAsk(toolkit, "next", "no-cancel");
    test:assertTrue(moved.includes("the toolkit stopped waiting for it"), moved);
    test:assertTrue(moved.includes("did not confirm that it was cancelled"), moved);
    test:assertFalse(moved.includes("so it was cancelled"), moved);
    test:assertTrue(moved.endsWith("Reply to the request you just sent: direct reply"), moved);
}

@test:Config {groups: ["a2a"]}
function testA2aAskDoesNotBringBackAConversationTheAgentRejected() returns error? {
    A2aToolKit toolkit = check new (a2aFaultCard());
    toolkit.store("rejected", {contextId: "gone-context"});
    // The agent rejects the conversation, the request is sent again as a new one, and the agent answers directly
    // with no context of its own.
    test:assertEquals(check a2aAsk(toolkit, "hello", "rejected"), "direct reply");
    test:assertEquals(toolkit.conversationOf("rejected")?.contextId, (),
            "the rejected conversation is not stored again");
    test:assertEquals(check a2aAsk(toolkit, "hello again", "rejected"), "direct reply");
}

@test:Config {groups: ["a2a"]}
function testA2aAskReturnsATaskThatFinishedWhileItWasBeingFollowed() returns error? {
    A2aToolKit toolkit = check new (a2aFaultCard());
    test:assertTrue((check a2aAsk(toolkit, "race", "finishes")).startsWith("[WORKING]"));
    // The first read finds the task running, and it cannot be followed. By the second read it has finished, and its
    // result comes with this call instead of one call later.
    string reply = check a2aAsk(toolkit, "next", "finishes");
    test:assertTrue(reply.includes("race done"), reply);
}

@test:Config {groups: ["a2a"]}
function testA2aCredentialsOverPlainHttpToAnotherHostAreFlagged() {
    test:assertTrue(isCleartextRemote("http://agents.example.com/planner"));
    test:assertTrue(isCleartextRemote("HTTP://10.0.0.5:8080/planner"));
    test:assertTrue(isCleartextRemote("http://user:pw@agents.example.com"));
    test:assertFalse(isCleartextRemote("https://agents.example.com/planner"));
    test:assertFalse(isCleartextRemote("http://localhost:9090"));
    test:assertFalse(isCleartextRemote("http://default-default.am-gateway.localhost:19080/weather"));
    test:assertFalse(isCleartextRemote("http://127.0.0.1:8000"));
    test:assertFalse(isCleartextRemote("http://127.1.2.3/agent"));
    // A name that begins with 127. is a hostname, not a loopback address, and neither is a malformed address.
    test:assertTrue(isCleartextRemote("http://127.agent.example/planner"));
    test:assertTrue(isCleartextRemote("http://127.0.0.256/planner"));
    test:assertTrue(isCleartextRemote("http://127.0.0/planner"));
    test:assertFalse(isCleartextRemote("http://[::1]:8000/agent"));
}

@test:Config {groups: ["a2a"]}
function testA2aAbandonNoticeSaysWhetherTheCancellationWasConfirmed() {
    test:assertTrue(abandonNotice(true).endsWith("so it was cancelled."), abandonNotice(true));
    test:assertTrue(abandonNotice(false).includes("did not confirm that it was cancelled"), abandonNotice(false));
    test:assertFalse(abandonNotice(false).includes("so it was cancelled"), abandonNotice(false));
}

@test:Config {groups: ["a2a"]}
function testA2aReadReturnsANewQuestionWhoseStatusEqualsTheOldOne() returns error? {
    A2aToolKit toolkit = check new (a2aFaultCard());
    // An agent that sets no message and no timestamp on its statuses: the second question's status equals the first.
    a2a:TaskStatus question = {state: a2a:TASK_STATE_INPUT_REQUIRED};
    a2a:Task old = {id: "t", contextId: "c", status: question};
    a2a:StreamResponse[] events = [
        old,
        <a2a:TaskStatusUpdateEvent>{taskId: "t", contextId: "c", status: {state: a2a:TASK_STATE_WORKING}},
        <a2a:TaskStatusUpdateEvent>{taskId: "t", contextId: "c", status: {state: a2a:TASK_STATE_INPUT_REQUIRED}}
    ];
    stream<a2a:StreamResponse, a2a:Error?> reply = events.toStream();
    A2aOutcome|a2a:Message|a2a:Error outcome = toolkit.read(reply, question);
    if outcome !is A2aOutcome {
        test:assertFail("expected the task, not a message or an error");
    }
    test:assertTrue(outcome.settled, "the new question is returned");
    test:assertEquals(outcome.task.status.state, a2a:TASK_STATE_INPUT_REQUIRED);

    // The old question alone, with nothing after it, is still not a new one.
    stream<a2a:StreamResponse, a2a:Error?> unchanged = [<a2a:StreamResponse>old].toStream();
    A2aOutcome|a2a:Message|a2a:Error stale = toolkit.read(unchanged, question);
    if stale !is A2aOutcome {
        test:assertFail("expected the task, not a message or an error");
    }
    test:assertFalse(stale.settled, "the old question is not settled");
}

@test:Config {groups: ["a2a"]}
function testA2aConversationLimitIsRestoredOnceBusyCallsEnd() returns error? {
    A2aToolKit toolkit = check new (a2aCard("Crowded"));
    foreach int i in 0 ..< A2A_MAX_CONVERSATIONS {
        string session = string `busy-${i}`;
        toolkit.store(session, {contextId: string `context-${i}`});
        test:assertTrue(toolkit.claim(session));
    }
    // Every conversation is in use, so none can be forgotten to make room.
    toolkit.store("extra", {contextId: "extra-context"});
    test:assertEquals(toolkit.conversationOf("busy-0")?.contextId, "context-0", "in use, so kept");
    foreach int i in 0 ..< A2A_MAX_CONVERSATIONS {
        toolkit.release(string `busy-${i}`);
    }
    // The excess is gone once the calls have ended: the least recently used one, and only that one.
    test:assertEquals(toolkit.conversationOf("busy-0"), {}, "the oldest idle conversation is forgotten");
    test:assertEquals(toolkit.conversationOf("busy-1")?.contextId, "context-1");
    test:assertEquals(toolkit.conversationOf("extra")?.contextId, "extra-context");
}
