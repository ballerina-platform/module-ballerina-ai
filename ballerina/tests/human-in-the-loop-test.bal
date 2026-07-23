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
import ballerina/time;

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

// `resume()` always takes a map keyed by `ApprovalRequest.id`, even when only one call is
// pending - there's no way to know upfront how many calls an LLM turn will propose or how
// many of them will need approval. This builds that single-entry map for tests that only
// ever have exactly one gated call pending.
function singleDecision(ApprovalRequiredError pending, HumanFeedback feedback) returns map<HumanFeedback> =>
    {[pending.detail().requests[0].id]: feedback};

@test:Config
function testHumanInTheLoopPauseCarriesTheProposedCall() returns error? {
    Agent agent = check newHitlTestAgent();
    string|Error result = agent.run("Refund order ORD-1", "hitl-pause-session");
    test:assertTrue(result is ApprovalRequiredError);
    if result is ApprovalRequiredError {
        ApprovalRequest[] requests = result.detail().requests;
        test:assertEquals(requests.length(), 1);
        ApprovalRequest req = requests[0];
        test:assertEquals(req.toolName, "issueRefund");
        test:assertEquals(req.arguments, {"orderId": "ORD-1", "amount": 50});
        test:assertEquals(req.sessionId, "hitl-pause-session");
        test:assertEquals(req.batchIndex, 0);
    }
}

@test:Config
function testHumanInTheLoopApprove() returns error? {
    Agent agent = check newHitlTestAgent();
    string sessionId = "hitl-approve-session";
    string|Error result = agent.run("Refund order ORD-1", sessionId);
    test:assertTrue(result is ApprovalRequiredError);

    string|Error resumed = result is ApprovalRequiredError
        ? agent.resume(sessionId, singleDecision(result, {approver: "tester"}))
        : result;
    test:assertTrue(resumed is string);
    if resumed is string {
        test:assertTrue(resumed.includes("Refunded 50.0 for ORD-1"), resumed);
    }

    // The approval should have been cleared on successful completion.
    ApprovalRequest[]? pending = check agent.getPendingApproval(sessionId);
    test:assertEquals(pending, ());
}

@test:Config
function testHumanInTheLoopRejectDoesNotExecuteTheTool() returns error? {
    Agent agent = check newHitlTestAgent();
    string sessionId = "hitl-reject-session";
    string|Error result = agent.run("Refund order ORD-1", sessionId);
    test:assertTrue(result is ApprovalRequiredError);

    string|Error resumed = result is ApprovalRequiredError
        ? agent.resume(sessionId, singleDecision(result, {feedback: "Not authorized for this order."}))
        : result;
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

    string|Error resumed = result is ApprovalRequiredError
        ? agent.resume(sessionId, singleDecision(result, {arguments: {"orderId": "ORD-1", "amount": 25}}))
        : result;
    test:assertTrue(resumed is string);
    if resumed is string {
        test:assertTrue(resumed.includes("Refunded 25.0 for ORD-1"), resumed);
    }
}

@test:Config
function testResumeWithoutPendingApprovalFails() returns error? {
    Agent agent = check newHitlTestAgent();
    string|Error resumed = agent.resume("no-such-hitl-session", {"any-id": {approver: "tester"}});
    test:assertTrue(resumed is ApprovalNotFoundError);
}

@test:Config
function testGetPendingApprovalIsNilWhenNothingIsPending() returns error? {
    Agent agent = check newHitlTestAgent();
    ApprovalRequest[]? pending = check agent.getPendingApproval("hitl-no-pending-session");
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

        ChatAssistantMessage|Error pausedOutput = pausedTrace.output;
        map<HumanFeedback> decision = pausedOutput is ApprovalRequiredError
            ? singleDecision(pausedOutput, {approver: "tester"})
            : {};
        Trace|Error resumedTrace = agent.resume(sessionId, decision, td = Trace);
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

    string|Error resumed = result is ApprovalRequiredError
        ? agent.resume(sessionId, singleDecision(result, {approver: "tester"}))
        : result;
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

isolated int hitlLookupOrderCallCount = 0;

isolated function countingLookupOrderMock(string orderId) returns string {
    lock {
        hitlLookupOrderCallCount += 1;
    }
    return string `Order ${orderId} found`;
}

isolated function getHitlLookupOrderCallCount() returns int {
    lock {
        return hitlLookupOrderCallCount;
    }
}

// The counter is module-level and shared across every test that uses `hitlCountingLookupOrderTool`;
// tests don't run in a guaranteed order, so each one must reset it before relying on its value.
isolated function resetHitlLookupOrderCallCount() {
    lock {
        hitlLookupOrderCallCount = 0;
    }
}

final ToolConfig hitlCountingLookupOrderTool = {
    name: "lookupOrder",
    description: "Looks up an order",
    parameters: {
        properties: {
            orderId: {'type: STRING}
        }
    },
    caller: countingLookupOrderMock
};

// Proposes a batch of [lookupOrder, issueRefund(gated), lookupOrder] in a single LLM response,
// then answers once all three observations are present in history.
public isolated client class HitlMixedBatchMockLLM {
    *ModelProvider;

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [],
            string? stop = ()) returns ChatAssistantMessage|Error {
        int functionMessageCount = messages is ChatUserMessage ? 0
            : messages.filter(msg => msg is ChatFunctionMessage).length();
        if functionMessageCount == 0 {
            return {
                role: ASSISTANT,
                toolCalls: [
                    {name: "lookupOrder", arguments: {"orderId": "ORD-1"}, id: "call-lookup-a"},
                    {name: "issueRefund", arguments: {"orderId": "ORD-1", "amount": 50}, id: "call-refund"},
                    {name: "lookupOrder", arguments: {"orderId": "ORD-2"}, id: "call-lookup-b"}
                ]
            };
        }
        return {role: ASSISTANT, content: "Done: " + functionMessageCount.toString() + " results"};
    }

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.lib.ai.MockGenerator"
    } external;
}

@test:Config
function testHumanInTheLoopMixedBatchGathersDecisionBeforeExecutingAnyCall() returns error? {
    resetHitlLookupOrderCallCount();
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new HitlMixedBatchMockLLM(),
        tools: [hitlCountingLookupOrderTool, hitlRefundTool]
    });
    string sessionId = "hitl-mixed-batch-session";

    string|Error result = agent.run("Refund order ORD-1 and look up ORD-2", sessionId);
    test:assertTrue(result is ApprovalRequiredError);
    if result is ApprovalRequiredError {
        ApprovalRequest[] requests = result.detail().requests;
        test:assertEquals(requests.length(), 1);
        test:assertEquals(requests[0].toolName, "issueRefund");
    }
    // Nothing in the batch has executed yet - not even the two safe `lookupOrder` calls -
    // since decisions are gathered before anything runs.
    test:assertEquals(getHitlLookupOrderCallCount(), 0);

    string|Error resumed = result is ApprovalRequiredError
        ? agent.resume(sessionId, singleDecision(result, {approver: "tester"}))
        : result;
    test:assertTrue(resumed is string);
    if resumed is string {
        // All three calls (both lookupOrder calls plus the resolved issueRefund) executed
        // together once the single gate was resolved.
        test:assertEquals(resumed, "Done: 3 results");
    }
    test:assertEquals(getHitlLookupOrderCallCount(), 2);
}

// Proposes two gated `issueRefund` calls together in one response, then answers once both
// observations are present in history.
public isolated client class HitlTwoGatesMockLLM {
    *ModelProvider;

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [],
            string? stop = ()) returns ChatAssistantMessage|Error {
        int functionMessageCount = messages is ChatUserMessage ? 0
            : messages.filter(msg => msg is ChatFunctionMessage).length();
        if functionMessageCount == 0 {
            return {
                role: ASSISTANT,
                toolCalls: [
                    {name: "issueRefund", arguments: {"orderId": "ORD-1", "amount": 50}, id: "call-refund-a"},
                    {name: "issueRefund", arguments: {"orderId": "ORD-2", "amount": 75}, id: "call-refund-b"}
                ]
            };
        }
        return {role: ASSISTANT, content: "Done: " + functionMessageCount.toString() + " refunds"};
    }

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.lib.ai.MockGenerator"
    } external;
}

@test:Config
function testHumanInTheLoopTwoGatesInOneBatchSurfacedTogether() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new HitlTwoGatesMockLLM(),
        tools: [hitlRefundTool]
    });
    string sessionId = "hitl-two-gates-session";

    // Both gated calls in the batch are surfaced together, in a single pause - not one at a time.
    string|Error result = agent.run("Refund ORD-1 and ORD-2", sessionId);
    test:assertTrue(result is ApprovalRequiredError);
    if result is ApprovalRequiredError {
        ApprovalRequest[] requests = result.detail().requests;
        test:assertEquals(requests.length(), 2);
        test:assertEquals(requests[0].arguments, {"orderId": "ORD-1", "amount": 50});
        test:assertEquals(requests[0].batchIndex, 0);
        test:assertEquals(requests[1].arguments, {"orderId": "ORD-2", "amount": 75});
        test:assertEquals(requests[1].batchIndex, 1);

        // A single bulk resume() call, keyed by each request's own id, resolves both at once -
        // no second round trip needed.
        map<HumanFeedback> decisions = {
            [requests[0].id]: {approver: "tester"},
            [requests[1].id]: {approver: "tester"}
        };
        string|Error resumed = agent.resume(sessionId, decisions);
        test:assertTrue(resumed is string);
        if resumed is string {
            test:assertEquals(resumed, "Done: 2 refunds");
        }
    }
}

@test:Config
function testHumanInTheLoopPartialBulkResumeLeavesRestPending() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new HitlTwoGatesMockLLM(),
        tools: [hitlRefundTool]
    });
    string sessionId = "hitl-two-gates-partial-session";

    string|Error result = agent.run("Refund ORD-1 and ORD-2", sessionId);
    test:assertTrue(result is ApprovalRequiredError);
    if result is ApprovalRequiredError {
        ApprovalRequest[] requests = result.detail().requests;
        test:assertEquals(requests.length(), 2);
        PendingApproval? firstPending = check agent.approvalStore.get(sessionId);
        test:assertTrue(firstPending is PendingApproval);
        int iterationsUsedAtFirstPause = firstPending is PendingApproval ? firstPending.iterationsUsed : -1;

        // Deciding only the first of the two pending requests leaves the second one pending,
        // rather than requiring every decision to arrive in the same resume() call.
        map<HumanFeedback> firstDecision = {[requests[0].id]: {approver: "tester"}};
        string|Error resumedOnce = agent.resume(sessionId, firstDecision);
        test:assertTrue(resumedOnce is ApprovalRequiredError);
        if resumedOnce is ApprovalRequiredError {
            ApprovalRequest[] stillPending = resumedOnce.detail().requests;
            test:assertEquals(stillPending.length(), 1);
            test:assertEquals(stillPending[0].id, requests[1].id);
            test:assertEquals(stillPending[0].arguments, {"orderId": "ORD-2", "amount": 75});
        }
        // No new `reason()` call happened between the two pauses, so the budget accounting
        // carried across them must be identical.
        PendingApproval? secondPending = check agent.approvalStore.get(sessionId);
        test:assertTrue(secondPending is PendingApproval);
        if secondPending is PendingApproval {
            test:assertEquals(secondPending.iterationsUsed, iterationsUsedAtFirstPause);
        }

        map<HumanFeedback> secondDecision = {[requests[1].id]: {approver: "tester"}};
        string|Error resumedTwice = agent.resume(sessionId, secondDecision);
        test:assertTrue(resumedTwice is string);
        if resumedTwice is string {
            test:assertEquals(resumedTwice, "Done: 2 refunds");
        }
    }
}

@test:Config
function testHumanInTheLoopPreservesParallelismForSafeCallsInGatedBatch() returns error? {
    MultiToolCallMockLLM scriptedModel = new;
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Answer the questions"},
        model: scriptedModel,
        tools: [slowSearchTool, slowCalculatorTool, hitlRefundTool],
        approval: {tools: ["Search", "Calculator"]}
    });
    string sessionId = "hitl-parallel-preserved-session";

    // `MultiToolCallMockLLM` always proposes Search + Calculator together; gating them (instead
    // of `issueRefund`, which never gets proposed here) still exercises the gathered-then-execute
    // path without needing a bespoke mock, since both calls now require approval.
    string|Error result = agent.run("Who is Leo DiCaprio's girlfriend, and what is 25 raised to the power of 0.43?",
            sessionId);
    test:assertTrue(result is ApprovalRequiredError);

    string|Error answer = "";
    if result is ApprovalRequiredError {
        // Both gated calls are surfaced together; resolve them both in one bulk resume() call.
        ApprovalRequest[] requests = result.detail().requests;
        test:assertEquals(requests.length(), 2);
        map<HumanFeedback> decisions = {};
        foreach ApprovalRequest req in requests {
            decisions[req.id] = {approver: "tester"};
        }
        answer = agent.resume(sessionId, decisions);
    }
    test:assertTrue(answer is string);
    if answer is string {
        test:assertEquals(answer, "Leo DiCaprio's girlfriend is Camila Morrone, and 25 raised to the " +
                "power of 0.43 is Answer: 3.991298452658078");
    }

    // Both tool executions overlapped in time, proving the resolved batch still ran with full
    // parallelism once every gate in it was decided.
    [decimal, decimal] searchWindow = check getToolExecutionWindow("Search");
    [decimal, decimal] calculatorWindow = check getToolExecutionWindow("Calculator");
    test:assertTrue(searchWindow[0] < calculatorWindow[1] && calculatorWindow[0] < searchWindow[1],
            string `Expected tool executions to overlap, but Search ran during ${searchWindow.toString()} ` +
            string `and Calculator ran during ${calculatorWindow.toString()}`);
}

// Proposes [lookupOrder, nonExistentTool] together; "nonExistentTool" is listed in
// `approval.tools` (so it looks gated by name) but isn't a registered tool at all.
public isolated client class HitlInvalidGateNameMockLLM {
    *ModelProvider;

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [],
            string? stop = ()) returns ChatAssistantMessage|Error {
        int functionMessageCount = messages is ChatUserMessage ? 0
            : messages.filter(msg => msg is ChatFunctionMessage).length();
        if functionMessageCount == 0 {
            return {
                role: ASSISTANT,
                toolCalls: [
                    {name: "lookupOrder", arguments: {"orderId": "ORD-1"}, id: "call-lookup"},
                    {name: "nonExistentTool", arguments: {}, id: "call-bogus"}
                ]
            };
        }
        return {role: ASSISTANT, content: "Done: " + functionMessageCount.toString() + " results"};
    }

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.lib.ai.MockGenerator"
    } external;
}

@test:Config
function testHumanInTheLoopGatedNameThatFailsValidationDoesNotPause() returns error? {
    resetHitlLookupOrderCallCount();
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Look up orders"},
        model: new HitlInvalidGateNameMockLLM(),
        tools: [hitlCountingLookupOrderTool],
        approval: {tools: ["nonExistentTool"]}
    });
    string sessionId = "hitl-invalid-gate-session";

    // "nonExistentTool" would look gated by name, but since it isn't a registered tool,
    // validation fails for it and it never actually pauses - the whole batch (including the
    // real `lookupOrder` call) proceeds straight to execution.
    string|Error result = agent.run("Look up order ORD-1", sessionId);
    test:assertTrue(result is string, result is Error ? result.message() : result.toString());
    if result is string {
        test:assertEquals(result, "Done: 2 results");
    }
}

isolated function secureRefundMock(string orderId, decimal amount) returns string {
    return string `Refunded ${amount} for ${orderId}`;
}

// Requires an OAuth scope but the agent has no credential/auth configuration to satisfy it,
// so `validateTool` fails it with `TokenAcquisitionError` (wrapped into `UnauthorizedError`)
// without any network call - deterministic to test.
final ToolConfig hitlSecureRefundTool = {
    name: "secureRefund",
    description: "Issues a refund that requires authorization",
    parameters: {
        properties: {
            orderId: {'type: STRING},
            amount: {'type: NUMBER}
        }
    },
    caller: secureRefundMock,
    auth: {scopes: "refund:write"}
};

// Proposes a gated `issueRefund` alongside an unrelated `secureRefund` call that will fail
// authorization once the resolved batch executes.
public isolated client class HitlAuthFailureMockLLM {
    *ModelProvider;

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [],
            string? stop = ()) returns ChatAssistantMessage|Error {
        return {
            role: ASSISTANT,
            toolCalls: [
                {name: "issueRefund", arguments: {"orderId": "ORD-1", "amount": 50}, id: "call-refund"},
                {name: "secureRefund", arguments: {"orderId": "ORD-2", "amount": 30}, id: "call-secure"}
            ]
        };
    }

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.lib.ai.MockGenerator"
    } external;
}

@test:Config
function testHumanInTheLoopUnauthorizedErrorInResolvedBatchEndsRunWithoutPersistingApproval() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new HitlAuthFailureMockLLM(),
        tools: [hitlRefundTool, hitlSecureRefundTool]
    });
    string sessionId = "hitl-auth-failure-session";

    // `issueRefund` is gated; `secureRefund` isn't, so triage pauses only on `issueRefund`.
    string|Error result = agent.run("Refund ORD-1 and ORD-2", sessionId);
    test:assertTrue(result is ApprovalRequiredError);

    // Once resolved, the batch executes together - `secureRefund`'s auth failure surfaces
    // exactly like it would in a non-HITL batch, with no interaction with the already-resolved
    // approval.
    string|Error resumed = result is ApprovalRequiredError
        ? agent.resume(sessionId, singleDecision(result, {approver: "tester"}))
        : result;
    test:assertTrue(resumed is string);
    if resumed is string {
        test:assertTrue(resumed.includes("authorization issue"), resumed);
    }
    // The run ended due to the auth failure - no pending approval should remain.
    ApprovalRequest[]? pending = check agent.getPendingApproval(sessionId);
    test:assertEquals(pending, ());
}

@test:Config
function testRunWhilePendingApprovalReturnsSamePause() returns error? {
    Agent agent = check newHitlTestAgent();
    string sessionId = "hitl-run-while-pending-session";

    string|Error firstResult = agent.run("Refund order ORD-1", sessionId);
    test:assertTrue(firstResult is ApprovalRequiredError);

    // A second, unrelated run() call on the same session must NOT start a new conversation
    // turn - it should surface the SAME pending approval instead of silently orphaning it
    // (or, worse, overwriting it with a second, unrelated pause under the same session key).
    string|Error secondResult = agent.run("What's the weather like?", sessionId);
    test:assertTrue(secondResult is ApprovalRequiredError);
    if firstResult is ApprovalRequiredError && secondResult is ApprovalRequiredError {
        test:assertEquals(secondResult.detail().requests[0].id, firstResult.detail().requests[0].id);
        test:assertEquals(secondResult.detail().requests[0].toolName, "issueRefund");
    }

    // The original pending approval is still exactly what it was.
    ApprovalRequest[]? stillPending = check agent.getPendingApproval(sessionId);
    test:assertTrue(stillPending is ApprovalRequest[]);
    if stillPending is ApprovalRequest[] && firstResult is ApprovalRequiredError {
        test:assertEquals(stillPending.length(), 1);
        test:assertEquals(stillPending[0].id, firstResult.detail().requests[0].id);
    }
}

@test:Config
function testRunClearsExpiredPendingApprovalAndProceeds() returns error? {
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new HitlMockLLM(),
        tools: [hitlRefundTool],
        approval: {timeout: -1}
    });
    string sessionId = "hitl-run-clears-expired-session";

    string|Error firstResult = agent.run("Refund order ORD-1", sessionId);
    test:assertTrue(firstResult is ApprovalRequiredError);

    // The pending approval is already expired the instant it's created (timeout: -1). A new
    // run() should clear it and proceed fresh, rather than surfacing the stale pause forever.
    string|Error secondResult = agent.run("Refund order ORD-1", sessionId);
    test:assertTrue(secondResult is ApprovalRequiredError);
    if firstResult is ApprovalRequiredError && secondResult is ApprovalRequiredError {
        // It's a genuinely new pause (fresh id), not the stale one being replayed.
        test:assertNotEquals(secondResult.detail().requests[0].id, firstResult.detail().requests[0].id);
    }

    // The same `timeout: -1` config applies to the second pause too, so it is also already
    // expired - resume() correctly classifies it as such (rather than "not found"), proving
    // the existing expiry handling in `resumeInternal` still works on top of the new guard.
    // The expiry check happens before id validation, so the id supplied here doesn't matter.
    string|Error resumed = agent.resume(sessionId, {"any-id": {approver: "tester"}});
    test:assertTrue(resumed is ApprovalExpiredError);
}

// A test-only store that always returns a deliberately corrupted `PendingApproval`
// (an out-of-range `historyPrefixLength` for an empty `history`) regardless of session ID,
// and tracks whether `remove` was ever called - used to exercise the fail-fast/self-healing
// behavior around corrupted state without reaching into `InMemoryApprovalStore`'s private
// state. Rebuilds the record fresh on every call instead of storing one directly, since
// `PendingApproval` isn't provably `Cloneable` (its `history: ChatMessage[]` may carry
// `Prompt`-typed content), so it can't be held in an `isolated class` field directly.
isolated class FixedApprovalStore {
    *ApprovalStore;
    private final string fixedId;
    private boolean removeCalled = false;

    isolated function init(string fixedId) {
        self.fixedId = fixedId;
    }

    private isolated function buildFixedApproval(string sessionId) returns PendingApproval => {
        sessionId,
        executionId: "corrupted-execution",
        iterationsUsed: 1,
        history: [],
        historyPrefixLength: 5,
        iterations: [],
        toolCalls: [],
        startTime: time:utcNow(),
        originalBatch: [{name: "issueRefund", arguments: {"orderId": "ORD-1", "amount": 50}, id: "call-1"}],
        pendingRequests: [
            {
                id: self.fixedId,
                sessionId,
                toolName: "issueRefund",
                toolDescription: "Issues a refund for an order",
                arguments: {"orderId": "ORD-1", "amount": 50},
                requestedAt: time:utcNow(),
                batchIndex: 0
            }
        ],
        decisions: [()]
    };

    public isolated function put(PendingApproval approval) returns Error? => ();

    public isolated function get(string sessionId) returns PendingApproval?|Error => self.buildFixedApproval(sessionId);

    public isolated function take(string sessionId) returns PendingApproval?|Error =>
        self.buildFixedApproval(sessionId);

    public isolated function remove(string sessionId) returns Error? {
        lock {
            self.removeCalled = true;
        }
        return ();
    }

    public isolated function wasRemoveCalled() returns boolean {
        lock {
            return self.removeCalled;
        }
    }
}

@test:Config
function testRunClearsCorruptedPendingApprovalAndProceeds() returns error? {
    string sessionId = "hitl-run-clears-corrupted-session";
    FixedApprovalStore store = new ("corrupted-approval-1");
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new HitlMockLLM(),
        tools: [hitlRefundTool],
        approval: {store}
    });

    // The pre-existing pending approval is corrupted (historyPrefixLength out of range for an
    // empty history). run() should clear it and proceed fresh rather than getting stuck.
    string|Error result = agent.run("Refund order ORD-1", sessionId);
    test:assertTrue(result is ApprovalRequiredError);
    if result is ApprovalRequiredError {
        test:assertNotEquals(result.detail().requests[0].id, "corrupted-approval-1");
    }
}

@test:Config
function testResumeFailsFastOnCorruptedHistory() returns error? {
    string sessionId = "hitl-resume-corrupted-session";
    FixedApprovalStore store = new ("corrupted-approval-2");
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new HitlMockLLM(),
        tools: [hitlRefundTool],
        approval: {store}
    });

    // The corrupted-history check happens before id validation, so the id supplied here
    // doesn't matter.
    string|Error resumed = agent.resume(sessionId, {"any-id": {approver: "tester"}});
    test:assertTrue(resumed is Error);
    test:assertFalse(resumed is ApprovalNotFoundError);
    if resumed is Error {
        test:assertTrue(resumed.message().includes("corrupted history"), resumed.message());
    }
}

@test:Config
function testGetPendingApprovalTreatsCorruptedAsAbsentWithoutMutating() returns error? {
    string sessionId = "hitl-get-corrupted-session";
    FixedApprovalStore store = new ("corrupted-approval-3");
    Agent agent = check new ({
        systemPrompt: {role: "Test Agent", instructions: "Handle refunds"},
        model: new HitlMockLLM(),
        tools: [hitlRefundTool],
        approval: {store}
    });

    ApprovalRequest[]? pending = check agent.getPendingApproval(sessionId);
    test:assertEquals(pending, ());
    test:assertFalse(store.wasRemoveCalled());
}

@test:Config
function testResumeClaimsApprovalPreventingDoubleExecution() returns error? {
    Agent agent = check newHitlTestAgent();
    string sessionId = "hitl-claim-once-session";
    string|Error result = agent.run("Refund order ORD-1", sessionId);
    test:assertTrue(result is ApprovalRequiredError);

    string|Error firstResume = result is ApprovalRequiredError
        ? agent.resume(sessionId, singleDecision(result, {approver: "tester"}))
        : result;
    test:assertTrue(firstResume is string);
    if firstResume is string {
        test:assertTrue(firstResume.includes("Refunded 50.0 for ORD-1"), firstResume);
    }

    // A second resume() for the same, already-claimed-and-resolved session must NOT
    // re-execute the tool - the approval was claimed (removed) exactly once, atomically,
    // by the first resume() call, before the tool ever ran. Reusing the same (now-stale) id
    // is fine for this assertion: nothing is pending anymore regardless of which id is named.
    string|Error secondResume = result is ApprovalRequiredError
        ? agent.resume(sessionId, singleDecision(result, {approver: "tester"}))
        : result;
    test:assertTrue(secondResume is ApprovalNotFoundError);
}

@test:Config
function testResumeWithUnknownApprovalIdFailsAndRestoresState() returns error? {
    Agent agent = check newHitlTestAgent();
    string sessionId = "hitl-unknown-id-session";

    string|Error result = agent.run("Refund order ORD-1", sessionId);
    test:assertTrue(result is ApprovalRequiredError);

    map<HumanFeedback> decisions = {"not-a-real-id": {approver: "tester"}};
    string|Error resumed = agent.resume(sessionId, decisions);
    test:assertTrue(resumed is UnknownApprovalIdError);

    // Nothing was resolved - the claimed approval must have been restored so a corrected
    // resume() call, using the real id, can still succeed afterward.
    if result is ApprovalRequiredError {
        map<HumanFeedback> correctedDecisions = {[result.detail().requests[0].id]: {approver: "tester"}};
        string|Error resolved = agent.resume(sessionId, correctedDecisions);
        test:assertTrue(resolved is string);
        if resolved is string {
            test:assertTrue(resolved.includes("Refunded 50.0 for ORD-1"), resolved);
        }
    }
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
