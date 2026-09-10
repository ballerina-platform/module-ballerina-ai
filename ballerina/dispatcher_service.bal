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

import ballerina/http;

# The HTTP response returned when a run pauses for human approval. Carries the pending approval
# requests in its body so the caller can gather decisions and resume via the `decision` resource.
#
# + body - The pending approval requests awaiting a decision
type ApprovalRequiredResponse record {|
    *http:Forbidden;
    record {|ApprovalRequest[] requests;|} body;
|};

# A stable discriminator a caller can branch on for a `Resume` that could not be applied.
type ResumeErrorType "ApprovalNotFoundError"|"UnknownApprovalIdError";

# The body of a 404/400 response for a `Resume` that could not be applied.
#
# + errorType - A stable discriminator a caller can branch on
# + message - Free text for humans; may be reworded independently, so it must not be relied on
#             for branching
type ResumeErrorBody record {|
    ResumeErrorType errorType;
    string message;
|};

# Internal service attached to the underlying `http:Listener` in place of the user's `ChatService`.
# For each request it forwards to the matching resource on the user's service (reflectively, via
# the native adaptor) and turns a paused run (`ApprovalRequiredError`) into an
# `ApprovalRequiredResponse`. This is what lets a user's chat service simply return the pause error
# and stay free of any HTTP error-to-response mapping.
#
# The dispatcher holds no Ballerina state: the user's `ChatService` is associated with it as native
# data by `Listener.attach`, keeping the dispatcher `isolated` so requests are served concurrently.
isolated service class ChatDispatcherService {
    *http:Service;

    isolated resource function post chat(@http:Payload ChatReqMessage request)
            returns ChatRespMessage|ApprovalRequiredResponse|http:NotFound|http:BadRequest|error {
        return toResponse(invokeChat(self, request));
    }

    isolated resource function post decision(@http:Payload DecisionMessage request)
            returns ChatRespMessage|ApprovalRequiredResponse|http:NotFound|http:BadRequest|error {
        return toResponse(invokeDecision(self, request));
    }
}

# Maps a resource result to the wire response: a paused run becomes an `ApprovalRequiredResponse`
# carrying the pending requests; a `Resume` sent for a session with nothing pending, or naming an
# id that isn't pending, maps to 404/400 respectively; anything else (a normal answer or a genuine
# error) passes through.
#
# + result - The result returned by the user service's resource
# + return - The mapped response for a pause or a resume mismatch, the `ChatRespMessage`, or the
#            original error
isolated function toResponse(ChatRespMessage|error result)
        returns ChatRespMessage|ApprovalRequiredResponse|http:NotFound|http:BadRequest|error {
    if result is ApprovalRequiredError {
        ApprovalRequiredResponse response = {body: {requests: result.detail().requests}};
        return response;
    }
    if result is ApprovalNotFoundError {
        ResumeErrorBody body = {errorType: "ApprovalNotFoundError", message: result.message()};
        http:NotFound response = {body};
        return response;
    }
    if result is UnknownApprovalIdError {
        ResumeErrorBody body = {errorType: "UnknownApprovalIdError", message: result.message()};
        http:BadRequest response = {body};
        return response;
    }
    return result;
}
