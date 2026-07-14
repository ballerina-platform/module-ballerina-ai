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
import ballerina/mcp;
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
function testHumanInTheLoopMergesTraceAcrossPause() returns error? {
    Agent agent = check newHitlTestAgent();
    string sessionId = "hitl-trace-merge-session";

    Trace|Error pausedTrace = agent.run("Refund order ORD-1", sessionId, td = Trace);
    test:assertTrue(pausedTrace is Trace);
    if pausedTrace is Trace {
        test:assertTrue(pausedTrace.output is ApprovalRequiredError);
        // Only the pause's own iteration has happened so far.
        test:assertEquals(pausedTrace.iterations.length(), 1);

        Trace|Error resumedTrace = agent.resume(sessionId, {approver: "tester"}, td = Trace);
        test:assertTrue(resumedTrace is Trace);
        if resumedTrace is Trace {
            // The merged trace covers the pre-pause iteration plus the two iterations that
            // happen on resume (the tool resolving, then the final answer) - not just the
            // iterations from this one call.
            test:assertEquals(resumedTrace.iterations.length(), 3);
            test:assertEquals(resumedTrace.id, pausedTrace.id);
            test:assertEquals(resumedTrace.startTime, pausedTrace.startTime);
            test:assertNotEquals(resumedTrace.endTime, pausedTrace.endTime);
        }
    }
}

isolated function lookupOrderMock(string orderId) returns string {
    return string `Order ${orderId} found`;
}

final ToolConfig hitlLookupOrderTool = {
    name: "lookupOrder",
    description: "Looks up an order",
    parameters: {
        properties: {
            orderId: {'type: STRING}
        }
    },
    caller: lookupOrderMock
};

// Proposes lookupOrder first (a normal, non-gated iteration), then the gated issueRefund
// (which pauses), then - once resumed - proposes lookupOrder again. With a tight `maxIter`,
// that last proposal should be discarded for exceeding the cap, spanning the pre-pause and
// post-resume iterations, rather than being judged solely on the post-resume call's own step count.
public isolated client class MaxIterMockLLM {
    *ModelProvider;

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [],
            string? stop = ()) returns ChatAssistantMessage|Error {
        ChatMessage[] msgs;
        if messages is ChatUserMessage {
            msgs = [messages];
        } else {
            msgs = messages;
        }
        int functionMessageCount = 0;
        foreach ChatMessage msg in msgs {
            if msg is ChatFunctionMessage {
                functionMessageCount += 1;
            }
        }
        if functionMessageCount == 0 {
            return {
                role: ASSISTANT,
                toolCalls: [{name: "lookupOrder", arguments: {"orderId": "ORD-1"}, id: "call-lookup-1"}]
            };
        }
        if functionMessageCount == 1 {
            return {
                role: ASSISTANT,
                toolCalls: [{name: "issueRefund", arguments: {"orderId": "ORD-1", "amount": 50}, id: "call-refund"}]
            };
        }
        // Proposes yet another step after resuming; this should never actually run once maxIter is hit.
        return {
            role: ASSISTANT,
            toolCalls: [{name: "lookupOrder", arguments: {"orderId": "ORD-1"}, id: "call-lookup-2"}]
        };
    }

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.lib.ai.MockGenerator"
    } external;
}

@test:Config
function testMaxIterExceededAfterResumeIsClassifiedCorrectly() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new MaxIterMockLLM(),
        tools: [hitlLookupOrderTool, hitlRefundTool],
        maxIter: 2
    });
    string sessionId = "hitl-maxiter-session";

    string|Error result = agent.run("Refund order ORD-1", sessionId);
    test:assertTrue(result is ApprovalRequiredError);

    string|Error resumed = agent.resume(sessionId, {approver: "tester"});
    test:assertTrue(resumed is MaxIterationExceededError);
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

@test:Config
function testGetDestructiveToolNamesFiltersByHint() returns error? {
    // Pure function, no live MCP server needed: only tools explicitly marked
    // `destructiveHint: true` are returned - a false hint, an absent hint, and no
    // annotations at all must all be excluded.
    mcp:ToolDefinition[] tools = [
        {name: "deleteResource", inputSchema: {'type: "object"}, annotations: {destructiveHint: true}},
        {name: "readResource", inputSchema: {'type: "object"}, annotations: {destructiveHint: false}},
        {name: "listResources", inputSchema: {'type: "object"}, annotations: {}},
        {name: "pingServer", inputSchema: {'type: "object"}}
    ];
    string[] destructiveToolNames = getDestructiveToolNames(tools);
    test:assertEquals(destructiveToolNames, ["deleteResource"]);
}
