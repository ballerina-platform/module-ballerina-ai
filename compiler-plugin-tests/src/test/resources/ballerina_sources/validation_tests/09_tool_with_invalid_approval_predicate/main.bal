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

// Parameter type mismatch (int amount vs the tool's decimal amount): invalid signature.
isolated function wrongType(string orderId, int amount) returns boolean => amount > 100;

// Returns int instead of boolean: invalid signature.
isolated function wrongReturn(string orderId, decimal amount) returns int => 1;

// Declares an extra ai:Context parameter that the tool does not have: signature mismatch.
isolated function withContext(ai:Context ctx, string orderId, decimal amount) returns boolean => true;

// Correct signature: must not raise a diagnostic.
isolated function correct(string orderId, decimal amount) returns boolean => amount > 100d;

@ai:AgentTool {requiresApproval: wrongType}
isolated function refundA(string orderId, decimal amount) returns string => "";

@ai:AgentTool {requiresApproval: wrongReturn}
isolated function refundB(string orderId, decimal amount) returns string => "";

@ai:AgentTool {requiresApproval: withContext}
isolated function refundC(string orderId, decimal amount) returns string => "";

@ai:AgentTool {requiresApproval: correct}
isolated function refundD(string orderId, decimal amount) returns string => "";
