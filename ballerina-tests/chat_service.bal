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
import ballerina/http;

listener http:Listener httpListener = http:getDefaultListener();
listener ai:Listener chatListener = new (httpListener);

service /chatService on chatListener {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        return {
            message: request.sessionId + ": " + request.message
        };
    }

    // Echoes the received decisions verbatim (keys, outcome, and reason), rather than just a
    // count, so tests can verify the `ApprovalRequest.id`-keyed contract survives the round trip.
    resource function post decision(@http:Payload ai:DecisionMessage request) returns ai:ChatRespMessage|error {
        string[] parts = [];
        foreach [string, ai:HumanDecision] [id, decision] in request.decisions.entries() {
            parts.push(id + "=" + decision.outcome.toString() + (decision?.reason ?: ""));
        }
        return {
            message: request.sessionId + ": " + string:'join(",", ...parts)
        };
    }
}

// A service whose `chat` resource returns an `ai:ApprovalRequiredError` (as a real agent would when
// it pauses for approval). The dispatcher inside `ai:Listener` should convert that error into a
// structured HTTP response carrying the pending requests - the service itself does no mapping.
// Two pending requests are returned, so tests can verify the dispatcher preserves a full batch
// rather than only the first entry.
service /pausingService on chatListener {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        return error ai:ApprovalRequiredError("Approval required", requests = [
            {id: "req-1", sessionId: request.sessionId, toolName: "issueRefund",
                toolDescription: "Refund an order", arguments: {"amount": 10}, batchIndex: 0},
            {id: "req-2", sessionId: request.sessionId, toolName: "cancelOrder",
                toolDescription: "Cancel an order", arguments: {"orderId": "ORD-1"}, batchIndex: 1}
        ]);
    }

    // Simulates the two resume-mismatch errors `ai:Agent.run()` raises for a `Resume`, keyed by
    // sessionId so a single resource can exercise both, without needing a real paused agent.
    resource function post decision(@http:Payload ai:DecisionMessage request) returns ai:ChatRespMessage|error {
        if request.sessionId == "no-pending" {
            return error ai:ApprovalNotFoundError("No pending approval found for session '" + request.sessionId + "'.");
        }
        return error ai:UnknownApprovalIdError("Unknown approval id for session '" + request.sessionId + "'.");
    }
}
