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

// Not mandated by the OpenTelemetry gen-ai spec: these spans make human-in-the-loop pauses
// visible in a trace, so a reader can see exactly where a run paused for approval and what the
// human decided when it resumed.

# Represents a tracing span for a run pausing to request human approval of one or more tool calls.
public isolated distinct class RequestHumanApprovalSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    # Initializes a new request-human-approval span for the given session.
    #
    # + sessionId - The session/conversation the pause belongs to
    isolated function init(string sessionId) {
        self.baseSpan = new (string `${REQUEST_HUMAN_APPROVAL} ${sessionId}`);
        self.addTag(OPERATION_NAME, REQUEST_HUMAN_APPROVAL);
        self.addTag(PROVIDER_NAME, "Ballerina");
        self.addTag(CONVERSATION_ID, sessionId);
    }

    # Records how many tool calls are awaiting a human decision.
    #
    # + count - The number of pending approval requests
    public isolated function addPendingCount(int count) {
        self.addTag(HITL_PENDING_COUNT, count);
    }

    # Records the pending approval requests (tool name, arguments, and id per request).
    #
    # + requests - The pending approval requests
    public isolated function addRequests(json requests) {
        self.addTag(HITL_REQUESTS, requests);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    # Closes the request-human-approval span and records its final status.
    #
    # + err - Optional error that indicates if the operation failed
    public isolated function close(error? err = ()) {
        self.baseSpan.close(err);
    }
}

# Represents a tracing span for resuming a paused run with the human's decisions.
public isolated distinct class ResolveHumanApprovalSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    # Initializes a new resolve-human-approval span for the given session.
    #
    # + sessionId - The session/conversation the resume belongs to
    isolated function init(string sessionId) {
        self.baseSpan = new (string `${RESOLVE_HUMAN_APPROVAL} ${sessionId}`);
        self.addTag(OPERATION_NAME, RESOLVE_HUMAN_APPROVAL);
        self.addTag(PROVIDER_NAME, "Ballerina");
        self.addTag(CONVERSATION_ID, sessionId);
    }

    # Records the human's decisions being applied on resume (tool name and decision per request).
    #
    # + decisions - The decisions applied in this resume
    public isolated function addDecisions(json decisions) {
        self.addTag(HITL_DECISIONS, decisions);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    # Closes the resolve-human-approval span and records its final status.
    #
    # + err - Optional error that indicates if the operation failed
    public isolated function close(error? err = ()) {
        self.baseSpan.close(err);
    }
}
