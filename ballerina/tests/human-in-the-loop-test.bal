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

import ballerina/jballerina.java;
import ballerina/test;

isolated function issueRefundMock(string orderId, decimal amount) returns string {
    return string `Refunded ${amount} for ${orderId}`;
}

final ToolConfig hitlRefundTool = {
    name: "issueRefund",
    description: "Issues a refund for an order",
    parameters: {
        properties: {
            orderId: {'type: STRING},
            amount: {'type: NUMBER}
        }
    },
    caller: issueRefundMock,
    requiresApproval: true
};

// Proposes the same `issueRefund` tool call on the first turn, then answers with the
// resulting observation once one is present in history (i.e., after the human's decision
// on the pending approval has been applied).
public isolated client class HitlMockLLM {
    *ModelProvider;

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [],
            string? stop = ()) returns ChatAssistantMessage|Error {
        ChatMessage[] msgs;
        if messages is ChatUserMessage {
            msgs = [messages];
        } else {
            msgs = messages;
        }
        ChatMessage lastMessage = msgs[msgs.length() - 1];
        if lastMessage is ChatFunctionMessage {
            return {role: ASSISTANT, content: "Observed: " + (lastMessage.content ?: "")};
        }
        return {
            role: ASSISTANT,
            toolCalls: [{name: "issueRefund", arguments: {"orderId": "ORD-1", "amount": 50}, id: "call-1"}]
        };
    }

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.lib.ai.MockGenerator"
    } external;
}

function newHitlTestAgent() returns Agent|error =>
    new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new HitlMockLLM(),
        tools: [hitlRefundTool]
    });

@test:Config
function testHumanInTheLoopPauseCarriesTheProposedCall() returns error? {
    Agent agent = check newHitlTestAgent();
    string|Error result = agent.run("Refund order ORD-1", "hitl-pause-session");
    test:assertTrue(result is ApprovalRequiredError);
    if result is ApprovalRequiredError {
        ApprovalRequest req = result.detail().request;
        test:assertEquals(req.toolName, "issueRefund");
        test:assertEquals(req.arguments, {"orderId": "ORD-1", "amount": 50});
        test:assertEquals(req.sessionId, "hitl-pause-session");
    }
}

@test:Config
function testHumanInTheLoopApprove() returns error? {
    Agent agent = check newHitlTestAgent();
    string sessionId = "hitl-approve-session";
    string|Error result = agent.run("Refund order ORD-1", sessionId);
    test:assertTrue(result is ApprovalRequiredError);

    string|Error resumed = agent.resume(sessionId, {approver: "tester"});
    test:assertTrue(resumed is string);
    if resumed is string {
        test:assertTrue(resumed.includes("Refunded 50.0 for ORD-1"), resumed);
    }

    // The approval should have been cleared on successful completion.
    ApprovalRequest? pending = check agent.getPendingApproval(sessionId);
    test:assertEquals(pending, ());
}

@test:Config
function testHumanInTheLoopRejectDoesNotExecuteTheTool() returns error? {
    Agent agent = check newHitlTestAgent();
    string sessionId = "hitl-reject-session";
    string|Error result = agent.run("Refund order ORD-1", sessionId);
    test:assertTrue(result is ApprovalRequiredError);

    string|Error resumed = agent.resume(sessionId, {feedback: "Not authorized for this order."});
    test:assertTrue(resumed is string);
    if resumed is string {
        test:assertTrue(resumed.includes("rejected"), resumed);
        test:assertTrue(resumed.includes("Not authorized for this order."), resumed);
        // The tool must not have run: no "Refunded" text should leak into the answer.
        test:assertFalse(resumed.includes("Refunded"));
    }
}

@test:Config
function testHumanInTheLoopEditArguments() returns error? {
    Agent agent = check newHitlTestAgent();
    string sessionId = "hitl-edit-session";
    string|Error result = agent.run("Refund order ORD-1", sessionId);
    test:assertTrue(result is ApprovalRequiredError);

    string|Error resumed = agent.resume(sessionId, {arguments: {"orderId": "ORD-1", "amount": 25}});
    test:assertTrue(resumed is string);
    if resumed is string {
        test:assertTrue(resumed.includes("Refunded 25.0 for ORD-1"), resumed);
    }
}

@test:Config
function testResumeWithoutPendingApprovalFails() returns error? {
    Agent agent = check newHitlTestAgent();
    string|Error resumed = agent.resume("no-such-hitl-session", {approver: "tester"});
    test:assertTrue(resumed is ApprovalNotFoundError);
}

@test:Config
function testGetPendingApprovalIsNilWhenNothingIsPending() returns error? {
    Agent agent = check newHitlTestAgent();
    ApprovalRequest? pending = check agent.getPendingApproval("hitl-no-pending-session");
    test:assertEquals(pending, ());
}

@test:Config
function testAgentWithoutApprovalToolsNeverPauses() returns error? {
    // A tool without `requiresApproval` should behave exactly as before HITL was added.
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Answer the questions"},
        model: new ScriptedMockLLM(),
        tools: [searchTool, calculatorTool]
    });
    string|Error result = agent.run("first turn query", "hitl-unaffected-session");
    test:assertEquals(result, "first turn answer");
}
