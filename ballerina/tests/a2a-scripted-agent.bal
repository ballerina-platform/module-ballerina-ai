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

// A real `a2a:RestListener` running a scripted agent, driven only by the
// message text -- so every generated tool is exercised against a real A2A
// wire exchange (this toolkit's own `a2a:RestClient` talking to a real
// `a2a:RestListener`), not a hand-mocked client.
//
// Triggers, matched on the message's joined text:
//   "echo <text>"  -> completes immediately with an artifact of <text>
//   "ask"          -> INPUT_REQUIRED; any follow-up on the same task
//                     completes with an artifact of the follow-up text
//   "draft"        -> an artifact, then INPUT_REQUIRED asking "which format?"
//   "slow"         -> WORKING, and never settles
//   "brief"        -> WORKING for a second, then completes with an artifact
//   "boom"         -> returns an a2a:Error (FAILED)
//   anything else  -> a direct a2a:Message reply, not a task at all

import ballerina/a2a;
import ballerina/lang.runtime;
import ballerina/test;

const int A2A_TOOLKIT_TEST_PORT = 19301;
final string a2aScriptedAgentUrl = string `http://localhost:${A2A_TOOLKIT_TEST_PORT}`;

final a2a:AgentCard a2aScriptedAgentCard = {
    name: "Scripted Agent",
    description: "A scripted A2A agent used to test A2aToolKit end to end",
    version: "1.0.0",
    skills: [
        {
            id: "script",
            name: "Script",
            description: "Follows fixed triggers",
            tags: ["test"],
            examples: ["echo hello", "ask", "boom"]
        }
    ],
    defaultInputModes: ["text"],
    defaultOutputModes: ["text"],
    capabilities: {streaming: true},
    supportedInterfaces: []
};

final a2a:DefaultHandler a2aScriptedAgentHandler = new (new A2aScriptedAgentExecutor());

listener a2a:RestListener a2aScriptedAgentListener = new (A2A_TOOLKIT_TEST_PORT);

isolated class A2aScriptedAgentExecutor {
    *a2a:AgentExecutor;

    public isolated function execute(a2a:RequestContext context, a2a:TaskUpdater updater)
            returns a2a:Message|a2a:Error? {
        string text = a2aScriptedText(context.message);
        a2aNoteRequest(text);

        if text.startsWith("echo ") {
            check updater.addArtifact([{text: text.substring(5)}]);
            check updater.complete();
            return;
        }
        if text == "ask" {
            check updater.requireInput({
                messageId: "scripted-ask",
                role: a2a:ROLE_AGENT,
                parts: [{text: "which one?"}]
            });
            return;
        }
        if text == "ids" {
            // Reports the conversation ids the caller sent, so a test can see what the toolkit carried over.
            string contextId = context.message.contextId ?: "none";
            string[] refs = context.message.referenceTaskIds ?: [];
            check updater.addArtifact([
                {text: string `context=${contextId} refs=${refs.length() == 0 ? "none" : string:'join(",", ...refs)}`}
            ]);
            check updater.complete();
            return;
        }
        if text == "draft" {
            // An artifact first, then a question: the question is what the caller needs to see.
            check updater.addArtifact([{text: "a partial draft"}]);
            check updater.requireInput({
                messageId: "scripted-draft",
                role: a2a:ROLE_AGENT,
                parts: [{text: "which format?"}]
            });
            return;
        }
        if text == "slow" {
            check updater.working();
            return;
        }
        if text == "brief" {
            a2aNoteBriefStarted();
            check updater.working();
            runtime:sleep(1);
            check updater.addArtifact([{text: "brief work finished"}]);
            check updater.complete();
            return;
        }
        if text == "boom" {
            string msg = "scripted agent failure";
            check updater.failed({messageId: "scripted-boom", role: a2a:ROLE_AGENT, parts: [{text: msg}]});
            return error a2a:InternalError(msg, message = msg);
        }
        // A continuation of "ask" (or anything not matching a trigger above)
        // lands here: reply directly with the text, completing the task.
        if context.message.taskId is string {
            check updater.addArtifact([{text}]);
            check updater.complete();
            return;
        }
        return {messageId: "scripted-direct-reply", role: a2a:ROLE_AGENT, parts: [{text: "direct: " + text}]};
    }
}

// The requests in the order they reached the handler, so a test can check the order calls were let through.
isolated string[] a2aRequestLog = [];

isolated function a2aNoteRequest(string text) {
    lock {
        a2aRequestLog.push(text);
    }
}

isolated function a2aRequestsSince(int count) returns string[] {
    lock {
        return a2aRequestLog.slice(count).cloneReadOnly();
    }
}

isolated function a2aRequestCount() returns int {
    lock {
        return a2aRequestLog.length();
    }
}

// How many "brief" requests reached the handler, so a test can wait for its own call to be in flight.
isolated int a2aBriefStarts = 0;

isolated function a2aNoteBriefStarted() {
    lock {
        a2aBriefStarts += 1;
    }
}

isolated function a2aBriefStartCount() returns int {
    lock {
        return a2aBriefStarts;
    }
}

isolated function a2aScriptedText(a2a:Message message) returns string {
    string text = "";
    foreach a2a:Part part in message.parts {
        string? t = part?.text;
        if t is string {
            text += t;
        }
    }
    return text;
}

@test:BeforeSuite
function attachA2aScriptedAgent() returns error? {
    check a2aScriptedAgentListener.attach(new A2aScriptedAgentOperations(a2aScriptedAgentHandler, a2aScriptedAgentCard));
}

isolated service class A2aScriptedAgentOperations {
    *a2a:Service;

    private final a2a:DefaultHandler handler;
    private final a2a:AgentCard & readonly card;

    isolated function init(a2a:DefaultHandler handler, a2a:AgentCard card) {
        self.handler = handler;
        self.card = card.cloneReadOnly();
    }

    isolated resource function get agentCard() returns a2a:AgentCard|a2a:Error {
        return self.card;
    }

    isolated resource function post message\:send(a2a:Context context, a2a:SendMessageRequest request)
            returns a2a:Task|a2a:Message|a2a:Error {
        return self.handler.handleSendMessage(context, request);
    }

    isolated resource function post message\:stream(a2a:Context context, a2a:SendMessageRequest request)
            returns stream<a2a:StreamResponse, a2a:Error?>|a2a:Error {
        return self.handler.handleSendStreamingMessage(context, request);
    }

    isolated resource function get tasks/[string id]/subscribe(a2a:Context context, a2a:SubscribeToTaskRequest request)
            returns stream<a2a:StreamResponse, a2a:Error?>|a2a:Error {
        return self.handler.handleSubscribeToTask(context, request);
    }

    isolated resource function get tasks/[string id](a2a:Context context, a2a:GetTaskRequest request)
            returns a2a:Task|a2a:Error {
        return self.handler.handleGetTask(context, request);
    }

    isolated resource function get tasks(a2a:Context context, a2a:ListTasksRequest request)
            returns a2a:ListTasksResponse|a2a:Error {
        return self.handler.handleListTasks(context, request);
    }

    isolated resource function post tasks/[string id]/cancel(a2a:Context context, a2a:CancelTaskRequest request)
            returns a2a:Task|a2a:Error {
        return self.handler.handleCancelTask(context, request);
    }

    isolated resource function post tasks/[string id]/pushNotificationConfigs(a2a:Context context, a2a:TaskPushNotificationConfig request)
            returns a2a:TaskPushNotificationConfig|a2a:Error {
        return self.handler.handleCreateTaskPushNotificationConfig(context, request);
    }

    isolated resource function get tasks/[string id]/pushNotificationConfigs/[string configId](a2a:Context context, a2a:GetTaskPushNotificationConfigRequest request)
            returns a2a:TaskPushNotificationConfig|a2a:Error {
        return self.handler.handleGetTaskPushNotificationConfig(context, request);
    }

    isolated resource function get tasks/[string id]/pushNotificationConfigs(a2a:Context context, a2a:ListTaskPushNotificationConfigsRequest request)
            returns a2a:ListTaskPushNotificationConfigsResponse|a2a:Error {
        return self.handler.handleListTaskPushNotificationConfigs(context, request);
    }

    isolated resource function delete tasks/[string id]/pushNotificationConfigs/[string configId](a2a:Context context, a2a:DeleteTaskPushNotificationConfigRequest request)
            returns a2a:Error? {
        return self.handler.handleDeleteTaskPushNotificationConfig(context, request);
    }
}
