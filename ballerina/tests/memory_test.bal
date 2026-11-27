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

const string K1 = "key1";
const string K2 = "key2";

const ChatSystemMessage K1SM1 = {role: SYSTEM, content: "You are a helpful assistant that is aware of the weather."};

const ChatUserMessage K1M1 = {role: USER, content: "Hello, my name is Alice. I'm from Seattle."};
final readonly & ChatAssistantMessage k1m2 = {role: ASSISTANT, content: "Hello Alice, what can I do for you?"};
const ChatUserMessage K1M3 = {role: USER, content: "I would like to know the weather today."};
final readonly & ChatAssistantMessage K1M4 = {role: ASSISTANT, 
        content: "The weather in Seattle today is mostly cloudy with occasional showers and a high around 58°F."};

const ChatUserMessage K2M1 = {role: USER, content: "Hello, my name is Bob."};

@test:Config
function testBasicShortTermMemory() returns error? {
    Memory memory = check new ShortTermMemory();

    check memory.update(K1, K1SM1);
    check memory.update(K1, K1M1);
    check memory.update(K2, K2M1);

    ChatMessage[] k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 2);
    assertChatMessageEquals(k1CurrentMemory[0], K1SM1);
    assertChatMessageEquals(k1CurrentMemory[1], K1M1);

    ChatMessage[] k2CurrentMemory = check memory.get(K2);
    test:assertEquals(k2CurrentMemory.length(), 1);
    assertChatMessageEquals(k2CurrentMemory[0], K2M1);

    // Check removal of all messages for a key.
    check memory.delete(K1);
    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 0);

    k2CurrentMemory = check memory.get(K2);
    test:assertEquals(k2CurrentMemory.length(), 1);
    assertChatMessageEquals(k2CurrentMemory[0], K2M1);

    // Add more messages to K1 after deletion.
    check memory.update(K1, k1m2);
    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 1);
    assertChatMessageEquals(k1CurrentMemory[0], k1m2);
}

@test:Config
function testShortTermMemoryWithInMemoryStoreTrimmingOnOverflow() returns error? {
    InMemoryShortTermMemoryStore store = check new (3);
    Memory memory = check new ShortTermMemory(store);

    check memory.update(K1, K1SM1);
    check memory.update(K1, K1M1);

    ChatMessage[] k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 2);
    assertChatMessageEquals(k1CurrentMemory[0], K1SM1);
    assertChatMessageEquals(k1CurrentMemory[1], K1M1);

    check memory.update(K1, k1m2);
    check memory.update(K1, K1M3);
    check memory.update(K2, K2M1);

    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 4);
    assertChatMessageEquals(k1CurrentMemory[0], K1SM1);
    assertChatMessageEquals(k1CurrentMemory[1], K1M1);
    assertChatMessageEquals(k1CurrentMemory[2], k1m2);
    assertChatMessageEquals(k1CurrentMemory[3], K1M3);

    // Overflows here
    check memory.update(K1, K1M4);

    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 4);
    assertChatMessageEquals(k1CurrentMemory[0], K1SM1);
    assertChatMessageEquals(k1CurrentMemory[1], k1m2);
    assertChatMessageEquals(k1CurrentMemory[2], K1M3);
    assertChatMessageEquals(k1CurrentMemory[3], K1M4);

    ChatMessage[] k2CurrentMemory = check memory.get(K2);
    test:assertEquals(k2CurrentMemory.length(), 1);
    assertChatMessageEquals(k2CurrentMemory[0], K2M1);
}

@test:Config
function testShortTermMemoryWithInMemoryStoreTrimmingOnOverflowWithBatchUpdate() returns error? {
    InMemoryShortTermMemoryStore store = check new (3);
    Memory memory = check new ShortTermMemory(store);

    check memory.update(K1, [K1SM1, K1M1]);

    ChatMessage[] k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 2);
    assertChatMessageEquals(k1CurrentMemory[0], K1SM1);
    assertChatMessageEquals(k1CurrentMemory[1], K1M1);

    check memory.update(K1, [k1m2, K1M3]);
    check memory.update(K2, K2M1);

    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 4);
    assertChatMessageEquals(k1CurrentMemory[0], K1SM1);
    assertChatMessageEquals(k1CurrentMemory[1], K1M1);
    assertChatMessageEquals(k1CurrentMemory[2], k1m2);
    assertChatMessageEquals(k1CurrentMemory[3], K1M3);

    // Overflows here
    check memory.update(K1, [K1M4, K1M1, k1m2]);

    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 4);
    assertChatMessageEquals(k1CurrentMemory[0], K1SM1);
    assertChatMessageEquals(k1CurrentMemory[1], K1M4);
    assertChatMessageEquals(k1CurrentMemory[2], K1M1);
    assertChatMessageEquals(k1CurrentMemory[3], k1m2);

    ChatMessage[] k2CurrentMemory = check memory.get(K2);
    test:assertEquals(k2CurrentMemory.length(), 1);
    assertChatMessageEquals(k2CurrentMemory[0], K2M1);
}

@test:Config
function testShortTermMemoryWithInMemoryStoreCustomTrimmingOnOverflow() returns error? {
    InMemoryShortTermMemoryStore store = check new (3);
    Memory memory = check new ShortTermMemory(store, <TrimOverflowHandlerConfiguration>{trimCount: 3});

    check memory.update(K1, K1M1);
    check memory.update(K1, k1m2);
    check memory.update(K1, K1M3);

    ChatMessage[] k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 3);
    assertChatMessageEquals(k1CurrentMemory[0], K1M1);
    assertChatMessageEquals(k1CurrentMemory[1], k1m2);
    assertChatMessageEquals(k1CurrentMemory[2], K1M3);

    // Overflows here
    check memory.update(K1, K1M4);

    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 1);
    assertChatMessageEquals(k1CurrentMemory[0], K1M4);
}

@test:Config
function testShortTermMemoryWithInMemoryStoreCustomTrimmingOnOverflowWithBatchUpdate() returns error? {
    InMemoryShortTermMemoryStore store = check new (3);
    Memory memory = check new ShortTermMemory(store, <TrimOverflowHandlerConfiguration>{trimCount: 3});

    check memory.update(K1, [K1M1, k1m2, K1M3]);

    ChatMessage[] k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 3);
    assertChatMessageEquals(k1CurrentMemory[0], K1M1);
    assertChatMessageEquals(k1CurrentMemory[1], k1m2);
    assertChatMessageEquals(k1CurrentMemory[2], K1M3);

    // Overflows here
    check memory.update(K1, [K1M4, K1M1]);

    k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 2);
    assertChatMessageEquals(k1CurrentMemory[0], K1M4);
    assertChatMessageEquals(k1CurrentMemory[1], K1M1);
}

@test:Config
function testShortTermMemoryWithIncomingBatchSizeLargerThanCapacity() returns error? {
    InMemoryShortTermMemoryStore store = check new (3);
    Memory memory = check new ShortTermMemory(store, <TrimOverflowHandlerConfiguration>{trimCount: 3});

    check memory.update(K1, [K1M1, k1m2, K1M3, K1M4]);
    ChatMessage[] k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 1);
    assertChatMessageEquals(k1CurrentMemory[0], K1M4);
}

@test:Config
function testShortTermMemorySummarizationStaysWithinCapacity() returns error? {
    final readonly & ChatAssistantMessage summary = {role: ASSISTANT, content: "Summary of the earlier conversation."};
    Memory memory = check new ShortTermMemory(check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {model: new MockSummarizerModel(summary)});

    ChatUserMessage question1 = {role: USER, content: "First question"};
    ChatAssistantMessage answer1 = {role: ASSISTANT, content: "First answer"};
    ChatUserMessage question2 = {role: USER, content: "Second question"};
    ChatAssistantMessage answer2 = {role: ASSISTANT, content: "Second answer"};
    ChatUserMessage question3 = {role: USER, content: "Third question"};
    ChatAssistantMessage answer3 = {role: ASSISTANT, content: "Third answer"};

    check memory.update(K1, [question1, answer1]);
    // A batch exactly the size of the capacity overflows the memory.
    check memory.update(K1, [question2, answer2, question3]);
    ChatMessage[] current = check memory.get(K1);
    test:assertTrue(current.length() <= 3, string `Expected at most 3 messages, found ${current.length()}`);
    assertChatMessageEquals(current[0], summary);
    assertChatMessageEquals(current[current.length() - 1], question3);

    // A batch whose size is a multiple of the capacity overflows it again.
    check memory.update(K1, [answer3, question1, answer1, question2, answer2, question3]);
    current = check memory.get(K1);
    test:assertTrue(current.length() <= 3, string `Expected at most 3 messages, found ${current.length()}`);
    assertChatMessageEquals(current[current.length() - 1], question3);
}

@test:Config
function testShortTermMemorySummarizationKeepsToolResultsWithTheirCall() returns error? {
    final readonly & ChatAssistantMessage summary = {role: ASSISTANT, content: "Summary of the earlier conversation."};
    Memory memory = check new ShortTermMemory(check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {model: new MockSummarizerModel(summary)});

    ChatUserMessage question = {role: USER, content: "What do I have on my plate today?"};
    ChatAssistantMessage toolCall = {role: ASSISTANT, toolCalls: [{name: "listTasks", arguments: {}}]};
    ChatFunctionMessage toolResult = {role: FUNCTION, name: "listTasks", content: "[]"};
    ChatFunctionMessage secondToolResult = {role: FUNCTION, name: "listTasks", content: "[]"};
    ChatAssistantMessage answer = {role: ASSISTANT, content: "You have nothing on your plate today."};

    // The summary keeps the stored user message after it, leaving room for only two incoming messages.
    check memory.update(K1, [answer, question]);
    check memory.update(K1, [toolCall, toolResult, answer]);
    ChatMessage[] current = check memory.get(K1);
    test:assertEquals(current.length(), 2);
    assertChatMessageEquals(current[0], summary);
    assertChatMessageEquals(current[1], answer);

    // Two tool results leave the second one at the start of the kept messages.
    check memory.delete(K1);
    check memory.update(K1, [question, toolCall, toolResult, secondToolResult, answer]);
    current = check memory.get(K1);
    test:assertEquals(current.length(), 2);
    assertChatMessageEquals(current[0], summary);
    assertChatMessageEquals(current[1], answer);

    // A single tool result that overflows is summarized with its tool call instead of being stored after the summary.
    check memory.delete(K1);
    check memory.update(K1, answer);
    check memory.update(K1, question);
    check memory.update(K1, toolCall);
    check memory.update(K1, toolResult);
    current = check memory.get(K1);
    test:assertEquals(current.length(), 1);
    assertChatMessageEquals(current[0], summary);

    // Any other message is still stored after the summary.
    check memory.update(K1, answer);
    check memory.update(K1, question);
    check memory.update(K1, toolCall);
    current = check memory.get(K1);
    test:assertEquals(current.length(), 3);
    assertChatMessageEquals(current[0], summary);
    assertChatMessageEquals(current[1], question);
    assertChatMessageEquals(current[2], toolCall);
}

@test:Config
function testShortTermMemoryBatchTrimWithTrimCountLargerThanHistory() returns error? {
    InMemoryShortTermMemoryStore store = check new (3);
    Memory memory = check new ShortTermMemory(store, <TrimOverflowHandlerConfiguration>{trimCount: 10});

    check memory.update(K1, [K1M1, k1m2, K1M3]);
    // Overflows with a trim count larger than the stored and incoming messages together.
    check memory.update(K1, [K1M4]);

    ChatMessage[] k1CurrentMemory = check memory.get(K1);
    test:assertEquals(k1CurrentMemory.length(), 1);
    assertChatMessageEquals(k1CurrentMemory[0], K1M4);
}

// One agent run with three rounds of two parallel tool calls: 11 messages, more than the default capacity of 10.
final readonly & ChatInteractiveMessage[] toolCallingRun = [
    {role: USER, content: "Plan a trip to Tokyo"},
    {role: ASSISTANT, toolCalls: [{name: "findAirportCodes", id: "call_1"}, {name: "lookupLocation", id: "call_2"}]},
    {role: FUNCTION, name: "findAirportCodes", id: "call_1", content: "HND, NRT"},
    {role: FUNCTION, name: "lookupLocation", id: "call_2", content: "35.68, 139.76"},
    {role: ASSISTANT, toolCalls: [{name: "searchFlights", id: "call_3"}, {name: "searchHotels", id: "call_4"}]},
    {role: FUNCTION, name: "searchFlights", id: "call_3", content: "4 offers"},
    {role: FUNCTION, name: "searchHotels", id: "call_4", content: "5 hotels"},
    {role: ASSISTANT, toolCalls: [{name: "getHotelRates", id: "call_5"}, {name: "getHotelRates", id: "call_6"}]},
    {role: FUNCTION, name: "getHotelRates", id: "call_5", content: "3 rates"},
    {role: FUNCTION, name: "getHotelRates", id: "call_6", content: "3 rates"},
    {role: ASSISTANT, content: "Here are the best options"}
];

final readonly & ChatUserMessage toolCallingRunFollowUp = {role: USER, content: "Try a cheaper hotel"};

@test:Config
function testShortTermMemoryTrimKeepsToolResultsWithTheirCall() returns error? {
    Memory single = check new ShortTermMemory();
    foreach ChatInteractiveMessage message in toolCallingRun {
        check single.update(K1, message);
    }
    check single.update(K1, toolCallingRunFollowUp);
    ChatMessage[] current = check single.get(K1);
    test:assertEquals(current.length(), 8);
    assertChatMessageEquals(current[0], toolCallingRun[4]);
    assertNoOrphanedToolResults(current, "one message at a time");

    Memory batch = check new ShortTermMemory();
    check batch.update(K1, toolCallingRun);
    check batch.update(K1, [toolCallingRunFollowUp]);
    current = check batch.get(K1);
    test:assertEquals(current.length(), 8);
    assertChatMessageEquals(current[0], toolCallingRun[4]);
    assertNoOrphanedToolResults(current, "batch updates");
}

@test:Config
function testShortTermMemoryTrimNeverStartsWithToolResult() returns error? {
    ChatInteractiveMessage[] wideToolCall = [
        {role: USER, content: "Compare four hotels"},
        {
            role: ASSISTANT,
            toolCalls: [
                {name: "getRate", id: "rate_1"},
                {name: "getRate", id: "rate_2"},
                {name: "getRate", id: "rate_3"},
                {name: "getRate", id: "rate_4"}
            ]
        },
        {role: FUNCTION, name: "getRate", id: "rate_1", content: "1"},
        {role: FUNCTION, name: "getRate", id: "rate_2", content: "2"},
        {role: FUNCTION, name: "getRate", id: "rate_3", content: "3"},
        {role: FUNCTION, name: "getRate", id: "rate_4", content: "4"},
        {role: ASSISTANT, content: "The second hotel is the cheapest"}
    ];
    ChatInteractiveMessage[] parallelToolCalls = [...toolCallingRun, toolCallingRunFollowUp, ...wideToolCall];
    // Agents store each tool call as an assistant message with that one call, followed by its result, and write
    // each run as one batch.
    ChatInteractiveMessage[][] agentRuns = [
        [
            {role: USER, content: "Plan a trip to Tokyo"},
            {role: ASSISTANT, toolCalls: [{name: "findAirportCodes", id: "agent_1"}]},
            {role: FUNCTION, name: "findAirportCodes", id: "agent_1", content: "HND, NRT"},
            {role: ASSISTANT, toolCalls: [{name: "searchFlights", id: "agent_2"}]},
            {role: FUNCTION, name: "searchFlights", id: "agent_2", content: "4 offers"},
            {role: ASSISTANT, toolCalls: [{name: "searchHotels", id: "agent_3"}]},
            {role: FUNCTION, name: "searchHotels", id: "agent_3", content: "5 hotels"},
            {role: ASSISTANT, content: "Here are the best options"}
        ],
        [
            {role: USER, content: "Try a cheaper hotel"},
            {role: ASSISTANT, toolCalls: [{name: "getHotelRates", id: "agent_4"}]},
            {role: FUNCTION, name: "getHotelRates", id: "agent_4", content: "3 rates"},
            {role: ASSISTANT, content: "This one is cheaper"}
        ]
    ];
    ChatInteractiveMessage[] agentToolCalls = [...agentRuns[0], ...agentRuns[1]];

    // The store requires a capacity of at least 3.
    foreach int capacity in 3 ... 13 {
        foreach int trimCount in 1 ... 13 {
            foreach [string, ChatInteractiveMessage[]] [shape, messages] in
                    [["parallel tool calls", parallelToolCalls], ["agent tool calls", agentToolCalls]] {
                string label = string `${shape}, capacity ${capacity}, trimCount ${trimCount}`;
                Memory single = check new ShortTermMemory(check new InMemoryShortTermMemoryStore(capacity),
                    <TrimOverflowHandlerConfiguration>{trimCount});
                Memory batch = check new ShortTermMemory(check new InMemoryShortTermMemoryStore(capacity),
                    <TrimOverflowHandlerConfiguration>{trimCount});
                foreach ChatInteractiveMessage message in messages {
                    check single.update(K1, message);
                    assertNoOrphanedToolResults(check single.get(K1), label + ", one message at a time");
                }
                foreach int batchSize in [2, 3, 5] {
                    check batch.delete(K1);
                    int index = 0;
                    while index < messages.length() {
                        check batch.update(K1, messages.slice(index, int:min(index + batchSize, messages.length())));
                        assertNoOrphanedToolResults(check batch.get(K1), string `${label}, batches of ${batchSize}`);
                        index += batchSize;
                    }
                }
            }

            string label = string `agent runs, capacity ${capacity}, trimCount ${trimCount}`;
            Memory runs = check new ShortTermMemory(check new InMemoryShortTermMemoryStore(capacity),
                <TrimOverflowHandlerConfiguration>{trimCount});
            foreach ChatInteractiveMessage[] run in agentRuns {
                check runs.update(K1, run);
                assertNoOrphanedToolResults(check runs.get(K1), label);
            }
        }
    }
}

@test:Config
function testShortTermMemoryTrimDropsToolCallThatDoesNotFit() returns error? {
    ChatAssistantMessage toolCall = {
        role: ASSISTANT,
        toolCalls: [{name: "getRate", id: "call_1"}, {name: "getRate", id: "call_2"}, {name: "getRate", id: "call_3"}]
    };
    ChatFunctionMessage result1 = {role: FUNCTION, name: "getRate", id: "call_1", content: "1"};
    ChatFunctionMessage result2 = {role: FUNCTION, name: "getRate", id: "call_2", content: "2"};
    ChatFunctionMessage result3 = {role: FUNCTION, name: "getRate", id: "call_3", content: "3"};
    ChatAssistantMessage answer = {role: ASSISTANT, content: "The rates are 1, 2, and 3."};

    // The tool call and its three results take four messages, more than the capacity of 3. Keeping the newest
    // result would separate it from its tool call, so nothing is kept.
    Memory single = check new ShortTermMemory(check new InMemoryShortTermMemoryStore(3));
    foreach ChatMessage message in [K1M1, toolCall, result1, result2, result3] {
        check single.update(K1, message);
    }
    test:assertEquals((check single.get(K1)).length(), 0);
    check single.update(K1, answer);
    ChatMessage[] current = check single.get(K1);
    test:assertEquals(current.length(), 1);
    assertChatMessageEquals(current[0], answer);

    Memory batch = check new ShortTermMemory(check new InMemoryShortTermMemoryStore(3));
    check batch.update(K1, [K1SM1, K1M1, toolCall, result1, result2, result3]);
    current = check batch.get(K1);
    test:assertEquals(current.length(), 1);
    assertChatMessageEquals(current[0], K1SM1);
}

@test:Config
function testShortTermMemoryDoesNotStoreLaterResultsOfARemovedToolCall() returns error? {
    ChatAssistantMessage toolCall = {
        role: ASSISTANT,
        toolCalls: [
            {name: "getRate", id: "call_1"},
            {name: "getRate", id: "call_2"},
            {name: "getRate", id: "call_3"},
            {name: "getRate", id: "call_4"}
        ]
    };
    ChatFunctionMessage result1 = {role: FUNCTION, name: "getRate", id: "call_1", content: "1"};
    ChatFunctionMessage result2 = {role: FUNCTION, name: "getRate", id: "call_2", content: "2"};
    ChatFunctionMessage result3 = {role: FUNCTION, name: "getRate", id: "call_3", content: "3"};
    ChatFunctionMessage result4 = {role: FUNCTION, name: "getRate", id: "call_4", content: "4"};

    // The third result removes the tool call along with everything else, since the tool call and its results do
    // not fit within the capacity of 3. The fourth result then fits, but its tool call is gone, so it is not stored.
    Memory single = check new ShortTermMemory(check new InMemoryShortTermMemoryStore(3));
    foreach ChatMessage message in [K1M1, toolCall, result1, result2, result3] {
        check single.update(K1, message);
    }
    test:assertEquals((check single.get(K1)).length(), 0);
    check single.update(K1, result4);
    test:assertEquals((check single.get(K1)).length(), 0);

    Memory batch = check new ShortTermMemory(check new InMemoryShortTermMemoryStore(3));
    check batch.update(K1, [K1M1, toolCall, result1, result2]);
    check batch.update(K1, [result3]);
    test:assertEquals((check batch.get(K1)).length(), 0);
    check batch.update(K1, [result4, k1m2]);
    ChatMessage[] current = check batch.get(K1);
    test:assertEquals(current.length(), 1);
    assertChatMessageEquals(current[0], k1m2);

    // A tool result is still stored after its tool call when memory is below capacity.
    check batch.delete(K1);
    check batch.update(K1, [K1M1, toolCall]);
    check batch.update(K1, [result1]);
    current = check batch.get(K1);
    test:assertEquals(current.length(), 3);
    assertChatMessageEquals(current[2], result1);
}

@test:Config
function testShortTermMemoryTrimDoesNotKeepToolResultsWithAnAssistantMessageWithoutToolCalls() returns error? {
    ChatAssistantMessage answer = {role: ASSISTANT, content: "Here you go"};
    ChatFunctionMessage result1 = {role: FUNCTION, name: "getRate", id: "call_1", content: "1"};
    ChatFunctionMessage result2 = {role: FUNCTION, name: "getRate", id: "call_2", content: "2"};
    ChatFunctionMessage result3 = {role: FUNCTION, name: "getRate", id: "call_3", content: "3"};

    // Tool results after an assistant message without tool calls are not stored.
    Memory memory = check new ShortTermMemory(check new InMemoryShortTermMemoryStore(4));
    check memory.update(K1, [K1M1, answer, result1]);
    ChatMessage[] current = check memory.get(K1);
    test:assertEquals(current.length(), 2);
    assertChatMessageEquals(current[1], answer);

    // A store may already hold such tool results, for example ones stored before they were rejected. Trimming three
    // messages lands on a tool result, and the assistant message before the tool results has no tool calls, so it
    // is not kept with them, although they would fit within the capacity of 4. No tool result can be kept without
    // a tool call, so nothing is kept.
    InMemoryShortTermMemoryStore store = check new (4);
    check store.put(K1, [K1M1, answer, result1, result2]);
    memory = check new ShortTermMemory(store, <TrimOverflowHandlerConfiguration>{trimCount: 3});
    check memory.update(K1, result3);
    test:assertEquals((check memory.get(K1)).length(), 0);
}

// Asserts that every stored tool result has its tool call in the stored history.
isolated function assertNoOrphanedToolResults(ChatMessage[] messages, string label) {
    string[] issuedCalls = [];
    foreach ChatMessage message in messages {
        if message is ChatAssistantMessage {
            foreach FunctionCall call in message.toolCalls ?: [] {
                issuedCalls.push(call.id ?: "");
            }
        } else if message is ChatFunctionMessage && issuedCalls.indexOf(message.id ?: "") is () {
            test:assertFail(string `${label}: tool result ${message.id ?: ""} is kept without its tool call`);
        }
    }
}

@test:Config
function testShortTermMemoryRejectsNonPositiveTrimCount() returns error? {
    ShortTermMemory|MemoryError memory = new (overflowConfiguration = <TrimOverflowHandlerConfiguration>{trimCount: 0});
    if memory !is MemoryError {
        test:assertFail("Expected a trim count of 0 to be rejected");
    }
    test:assertTrue(memory.message().includes("trimCount"), "Expected the error to name trimCount: " + memory.message());
}

const CHAT_METHOD = "chat";

@test:Config
function testShortTermMemoryWithSummarizationOnOverflow1() returns error? {
    final readonly & ChatAssistantMessage memorySummaryMessage = {
        role: ASSISTANT,
        content: string `The user inquired about their tasks for the day. The AI assistant retrieved and 
            listed the user's tasks, which are:

            1. **Buy groceries** - Completed
            2. **Finish the project report** - Due by October 20, 2025
            3. **Call Alice** - Due by October 21, 2025

            The assistant offered further assistance if needed.`
    };

    final readonly & ChatSystemMessage ksm1 = {
        role: SYSTEM, 
        content: string `
            # Role  
            Task Assistant  

            # Instructions  
            You are a helpful assistant that guides users with their todo lists.`
    };

    final readonly & ChatUserMessage km1 = {
        role: USER, 
        content: "Hello, what do I have on my plate today?"
    };

    final readonly & ChatAssistantMessage km2 = {
        role: ASSISTANT,
        toolCalls: [
            {
                name: "listTasks",
                arguments: {}
            }
        ]
    };

    final readonly & ChatFunctionMessage km3 = {
        role: FUNCTION,
        name: "listTasks",
        content: "[{\"description\":\"Buy groceries\",\"dueBy\":\"2025-10-19\",\"completed\":true}," +
            "{\"description\":\"Finish the project report\",\"dueBy\":\"2025-10-20\",\"completed\":false}," +
            "{\"description\":\"Call Alice\",\"dueBy\":\"2025-10-21\",\"completed\":false}]"
    };

    final readonly & ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: string `
            Today, you have the following task on your plate:

            1. **Finish the project report** - Due by **October 20, 2025**.

            Let me know if you need help with anything!`
    };

    InMemoryShortTermMemoryStore store = check new (4);
    ModelProvider model = isolated client object {
        isolated remote function chat(
                ChatMessage[]|ChatUserMessage messages, 
                ChatCompletionFunctions[] tools, string? stop) returns ChatAssistantMessage|Error {
            assertSummarizationRequestChatMessages(messages, [km1, km2, km3, km4], defaultSummarizationPrompt);
            return memorySummaryMessage;                    
        }

        isolated remote function generate(Prompt prompt, typedesc<anydata> td) returns td|Error = external;
    };

    Memory memory = check new ShortTermMemory(
        store,
        overflowConfiguration = {
            model
        }
    );
    
    final string k = "key";

    check memory.update(k, ksm1);
    check memory.update(k, km1);
    check memory.update(k, km2);
    check memory.update(k, km3);
    check memory.update(k, km4);

    ChatMessage[] k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 5);
    assertChatMessageEquals(k3CurrentMemory[0], ksm1);
    assertChatMessageEquals(k3CurrentMemory[1], km1);
    assertChatMessageEquals(k3CurrentMemory[2], km2);
    assertChatMessageEquals(k3CurrentMemory[3], km3);
    assertChatMessageEquals(k3CurrentMemory[4], km4);

    final readonly & ChatUserMessage km5 = {
        role: USER,
        content: "What about tomorrow?"
    };
    check memory.update(k, km5);

    k3CurrentMemory = check memory.get(k);    
    test:assertEquals(k3CurrentMemory.length(), 3);
    assertChatMessageEquals(k3CurrentMemory[0], ksm1);
    assertChatMessageEquals(k3CurrentMemory[1], memorySummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[2], km5);
}

@test:Config
function testShortTermMemoryWithSummarizationOnOverflow1WithBatchUpdate() returns error? {
    final readonly & ChatAssistantMessage memorySummaryMessage = {
        role: ASSISTANT,
        content: string `The user inquired about their tasks for the day. The AI assistant retrieved and 
            listed the user's tasks, which are:

            1. **Buy groceries** - Completed
            2. **Finish the project report** - Due by October 20, 2025
            3. **Call Alice** - Due by October 21, 2025

            The assistant offered further assistance if needed.`
    };

    final readonly & ChatSystemMessage ksm1 = {
        role: SYSTEM,
        content: string `
            # Role  
            Task Assistant  

            # Instructions  
            You are a helpful assistant that guides users with their todo lists.`
    };

    final readonly & ChatUserMessage km1 = {
        role: USER,
        content: "Hello, what do I have on my plate today?"
    };

    final readonly & ChatAssistantMessage km2 = {
        role: ASSISTANT,
        toolCalls: [
            {
                name: "listTasks",
                arguments: {}
            }
        ]
    };

    final readonly & ChatFunctionMessage km3 = {
        role: FUNCTION,
        name: "listTasks",
        content: "[{\"description\":\"Buy groceries\",\"dueBy\":\"2025-10-19\",\"completed\":true}," +
            "{\"description\":\"Finish the project report\",\"dueBy\":\"2025-10-20\",\"completed\":false}," +
            "{\"description\":\"Call Alice\",\"dueBy\":\"2025-10-21\",\"completed\":false}]"
    };

    final readonly & ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: string `
            Today, you have the following task on your plate:

            1. **Finish the project report** - Due by **October 20, 2025**.

            Let me know if you need help with anything!`
    };

    InMemoryShortTermMemoryStore store = check new (4);
    ModelProvider model = isolated client object {
        isolated remote function chat(
                ChatMessage[]|ChatUserMessage messages,
                ChatCompletionFunctions[] tools, string? stop) returns ChatAssistantMessage|Error {
            assertSummarizationRequestChatMessages(messages, [km1, km2, km3, km4], defaultSummarizationPrompt);
            return memorySummaryMessage;
        }

        isolated remote function generate(Prompt prompt, typedesc<anydata> td) returns td|Error = external;
    };

    Memory memory = check new ShortTermMemory(
        store,
        overflowConfiguration = {
            model
        }
    );

    final string k = "key";

    ChatMessage[] k3CurrentMemory = check memory.get(k);

    final readonly & ChatUserMessage km5 = {
        role: USER,
        content: "What about tomorrow?"
    };
    check memory.update(k, [ksm1, km1, km2, km3, km4, km5]);

    k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 3);
    assertChatMessageEquals(k3CurrentMemory[0], ksm1);
    assertChatMessageEquals(k3CurrentMemory[1], memorySummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[2], km5);
}

@test:Config
function testShortTermMemoryWithSummarizationOnOverflow2() returns error? {
    final readonly & ChatAssistantMessage memorySummaryMessage = {
        role: ASSISTANT,
        content: string `"**Summary of Chat History:**
                1. **User Inquiry:** The user asked the AI about their tasks for the day.
                
                2. **AI Response:** The AI checked the user's task list.

                3. **Tasks Listed:**
                - **Completed Tasks:**
                    - Buy groceries (due by 2025-10-19)
                - **Pending Tasks:**
                    - Finish the project report (due by 2025-10-20)
                    - Call Alice (due by 2025-10-21)`
    };

    Memory memory = check new ShortTermMemory(
        check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {
            model: new MockSummarizerModel(memorySummaryMessage)
        }
    );
    
    final string k = "key";

    final readonly & ChatUserMessage km1 = {
        role: USER, 
        content: "Hello, what do I have on my plate today?"
    };
    check memory.update(k, km1);

    final readonly & ChatAssistantMessage km2 = {
        role: ASSISTANT,
        toolCalls: [
            {
                name: "listTasks",
                arguments: {}
            }
        ]
    };
    check memory.update(k, km2);

    final readonly & ChatFunctionMessage km3 = {
        role: FUNCTION,
        name: "listTasks",
        content: "[{\"description\":\"Buy groceries\",\"dueBy\":\"2025-10-19\",\"completed\":true}," +
            "{\"description\":\"Finish the project report\",\"dueBy\":\"2025-10-20\",\"completed\":false}," +
            "{\"description\":\"Call Alice\",\"dueBy\":\"2025-10-21\",\"completed\":false}]"
    };
    check memory.update(k, km3);

    ChatMessage[] k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 3);
    assertChatMessageEquals(k3CurrentMemory[0], km1);
    assertChatMessageEquals(k3CurrentMemory[1], km2);
    assertChatMessageEquals(k3CurrentMemory[2], km3);

    final readonly & ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: string `
            Today, you have the following task on your plate:

            1. **Finish the project report** - Due by **October 20, 2025**.

            Let me know if you need help with anything!`
    };
    check memory.update(k, km4);

    k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 2);
    assertChatMessageEquals(k3CurrentMemory[0], memorySummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[1], km4);
}

@test:Config
function testShortTermMemoryWithSummarizationOnOverflow2OnBatchUpdate() returns error? {
    final readonly & ChatAssistantMessage memorySummaryMessage = {
        role: ASSISTANT,
        content: string `"**Summary of Chat History:**
                1. **User Inquiry:** The user asked the AI about their tasks for the day.
                
                2. **AI Response:** The AI checked the user's task list.

                3. **Tasks Listed:**
                - **Completed Tasks:**
                    - Buy groceries (due by 2025-10-19)
                - **Pending Tasks:**
                    - Finish the project report (due by 2025-10-20)
                    - Call Alice (due by 2025-10-21)`
    };

    Memory memory = check new ShortTermMemory(
        check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {
            model: new MockSummarizerModel(memorySummaryMessage)
        }
    );

    final string k = "key";

    final readonly & ChatUserMessage km1 = {
        role: USER,
        content: "Hello, what do I have on my plate today?"
    };

    final readonly & ChatAssistantMessage km2 = {
        role: ASSISTANT,
        toolCalls: [
            {
                name: "listTasks",
                arguments: {}
            }
        ]
    };

    final readonly & ChatFunctionMessage km3 = {
        role: FUNCTION,
        name: "listTasks",
        content: "[{\"description\":\"Buy groceries\",\"dueBy\":\"2025-10-19\",\"completed\":true}," +
            "{\"description\":\"Finish the project report\",\"dueBy\":\"2025-10-20\",\"completed\":false}," +
            "{\"description\":\"Call Alice\",\"dueBy\":\"2025-10-21\",\"completed\":false}]"
    };

    final readonly & ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: string `
            Today, you have the following task on your plate:

            1. **Finish the project report** - Due by **October 20, 2025**.

            Let me know if you need help with anything!`
    };
    check memory.update(k, [km1, km2, km3, km4]);

    ChatMessage[] k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 2);
    assertChatMessageEquals(k3CurrentMemory[0], memorySummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[1], km4);
}

// Tests preserving the last user message when summarizing on overflow.
@test:Config
function testShortTermMemoryWithSummarizationOnOverflow3() returns error? {
    final readonly & ChatAssistantMessage memorySummaryMessage = {
        role: ASSISTANT,
        content: string `Joy asked the AI for a book recommendation. The AI responded 
            by asking for Joy's preferred genre to provide a suitable suggestion.`
    };

    Memory memory = check new ShortTermMemory(
        check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {
            model: new MockSummarizerModel(memorySummaryMessage)
        }
    );
    
    final string k = "key";

    ChatUserMessage km1 = {
        role: USER,
        content: "Hello, I'm Joy. Can you recommend me a good book to read?"
    };
    check memory.update(k, km1);
    
    ChatAssistantMessage km2 = {
        role: ASSISTANT,
        content: "Hi Joy! Sure, what genre are you interested in?"
    };
    check memory.update(k, km2);

    ChatUserMessage km3 = {
        role: USER,
        content: "I enjoy science fiction and fantasy."
    };
    check memory.update(k, km3);

    ChatMessage[] k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 3);
    assertChatMessageEquals(k3CurrentMemory[0], km1);
    assertChatMessageEquals(k3CurrentMemory[1], km2);
    assertChatMessageEquals(k3CurrentMemory[2], km3);

    ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: string `Great choices! I recommend Arthur C. Clarke's '2001: A Space Odyssey' 
            for science fiction and J.R.R. Tolkien's 'The Hobbit' for fantasy.`
    };
    check memory.update(k, km4);

    k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 3);
    assertChatMessageEquals(k3CurrentMemory[0], memorySummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[1], km3);
    assertChatMessageEquals(k3CurrentMemory[2], km4);
}

@test:Config
function testShortTermMemoryWithSummarizationOnOverflow3OnBatchUpdate() returns error? {
    final readonly & ChatAssistantMessage memorySummaryMessage = {
        role: ASSISTANT,
        content: string `Joy asked the AI for a book recommendation. The AI responded 
            by asking for Joy's preferred genre to provide a suitable suggestion.`
    };

    Memory memory = check new ShortTermMemory(
        check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {
            model: new MockSummarizerModel(memorySummaryMessage)
        }
    );

    final string k = "key";

    ChatUserMessage km1 = {
        role: USER,
        content: "Hello, I'm Joy. Can you recommend me a good book to read?"
    };

    ChatAssistantMessage km2 = {
        role: ASSISTANT,
        content: "Hi Joy! Sure, what genre are you interested in?"
    };

    ChatUserMessage km3 = {
        role: USER,
        content: "I enjoy science fiction and fantasy."
    };

    ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: string `Great choices! I recommend Arthur C. Clarke's '2001: A Space Odyssey' 
            for science fiction and J.R.R. Tolkien's 'The Hobbit' for fantasy.`
    };
    check memory.update(k, [km1, km2, km3, km4]);

    ChatMessage[] k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 3);
    assertChatMessageEquals(k3CurrentMemory[0], memorySummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[1], km3);
    assertChatMessageEquals(k3CurrentMemory[2], km4);
}

@test:Config
function testOverridingSummarizationPrompt() returns error? {
    final readonly & Prompt customSummarizationPrompt = `Summarize the following conversation in brief: `;
    
    final readonly & ChatAssistantMessage mockSummaryMessage = {
        role: ASSISTANT,
        content: string `The user asked about their tasks for the day, and the assistant responded by 
        listing one task: to buy groceries, which is due by October 19, 2025, and is not yet completed.`
    };

    final string k = "key";

    final readonly & ChatUserMessage km1 = {
        role: USER, 
        content: "Hello, what do I have on my plate today?"
    };

    final readonly & ChatAssistantMessage km2 = {
        role: ASSISTANT,
        toolCalls: [
            {
                name: "listTasks",
                arguments: {}
            }
        ]
    };

    final readonly & ChatFunctionMessage km3 = {
        role: FUNCTION,
        name: "listTasks",
        content: "[{\"description\":\"Buy groceries\",\"dueBy\":\"2025-10-19\",\"completed\":false}]"
    };

    ModelProvider model = isolated client object {
        isolated remote function chat(
                ChatMessage[]|ChatUserMessage messages, 
                ChatCompletionFunctions[] tools, string? stop) returns ChatAssistantMessage|Error {
            assertSummarizationRequestChatMessages(messages, [km1, km2, km3], customSummarizationPrompt);
            return mockSummaryMessage;                    
        }

        isolated remote function generate(Prompt prompt, typedesc<anydata> td) returns td|Error = external;
    };

    Memory memory = check new ShortTermMemory(
        check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {
            model,
            prompt: customSummarizationPrompt
        }
    );

    check memory.update(k, km1);
    check memory.update(k, km2);
    check memory.update(k, km3);

    final readonly & ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: "You have one pending task: Buy groceries."
    };
    check memory.update(k, km4);

    ChatMessage[] k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 2);
    assertChatMessageEquals(k3CurrentMemory[0], mockSummaryMessage);
    assertChatMessageEquals(k3CurrentMemory[1], km4);
}

@test:Config
function testDefaultingToTheDefaultModelForSummarization() returns error? {
    Memory|MemoryError memory = new ShortTermMemory(
        check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {
            prompt: `Summarize the following conversation briefly`
            // No model provided here, should default to the default model.
            // Since the model is not configured, should error out.
        }
    );

    if memory is Memory {
        test:assertFail("Expected 'MemoryError' but found 'Memory'");
    }

    test:assertEquals(memory.message(), 
        "Failed to initialize short term memory: The `ballerina.ai.wso2ProviderConfig` is not configured correctly. " +
            "Ensure values are configured for the WSO2 model provider configurable variable");
}

@test:Config
function testSummarizationFailure() returns error? {
    final string k = "key";

    final readonly & ChatUserMessage km1 = {
        role: USER, 
        content: "Hello, what do I have on my plate today?"
    };

    final readonly & ChatAssistantMessage km2 = {
        role: ASSISTANT,
        toolCalls: [
            {
                name: "listTasks",
                arguments: {}
            }
        ]
    };

    final readonly & ChatFunctionMessage km3 = {
        role: FUNCTION,
        name: "listTasks",
        content: "[{\"description\":\"Buy groceries\",\"dueBy\":\"2025-10-19\",\"completed\":false}]"
    };

    ModelProvider model = isolated client object {
        isolated remote function chat(
                ChatMessage[]|ChatUserMessage messages, 
                ChatCompletionFunctions[] tools, string? stop) returns ChatAssistantMessage|Error {
            assertSummarizationRequestChatMessages(messages, [km1, km2, km3], defaultSummarizationPrompt);
            return error("Simulated summarization failure");                    
        }

        isolated remote function generate(Prompt prompt, typedesc<anydata> td) returns td|Error = external;
    };

    Memory memory = check new ShortTermMemory(
        check new InMemoryShortTermMemoryStore(3),
        overflowConfiguration = {model}
    );

    check memory.update(k, km1);
    check memory.update(k, km2);
    check memory.update(k, km3);

    final readonly & ChatAssistantMessage km4 = {
        role: ASSISTANT,
        content: "You have one pending task: Buy groceries."
    };
    MemoryError? err = memory.update(k, km4);
    if err is () {
        test:assertFail("Expected 'MemoryError' but found '()'");
    }

    test:assertEquals(err.message(), "Failed to generate summary: Simulated summarization failure");

    ChatMessage[] k3CurrentMemory = check memory.get(k);
    test:assertEquals(k3CurrentMemory.length(), 3);
    assertChatMessageEquals(k3CurrentMemory[0], km1);
    assertChatMessageEquals(k3CurrentMemory[1], km2);
    assertChatMessageEquals(k3CurrentMemory[2], km3);
}

isolated function assertSummarizationRequestChatMessages(ChatMessage[]|ChatUserMessage messages, 
                                                         ChatInteractiveMessage[] expectedHistory,
                                                         Prompt summarizationPrompt) {
    if messages is ChatUserMessage {
        test:assertFail("Expected ChatMessage[] but found ChatUserMessage");
    }
    test:assertEquals(messages.length(), 2);
    
    ChatMessage message0 = messages[0];
    if message0 !is ChatSystemMessage {
        test:assertFail("Expected first message to be ChatSystemMessage");
    }
    string|Prompt prompt = message0.content;
    test:assertEquals(prompt is string ? prompt : toString(prompt), toString(summarizationPrompt));

    ChatMessage message1 = messages[1];
    if message1 !is ChatUserMessage {
        test:assertFail("Expected first message to be ChatUserMessage");
    }
    prompt = message1.content;
    test:assertEquals(prompt is string ? prompt : toString(prompt), 
                        toString(`Summarize this chat history: ${expectedHistory.toString()}`));
}

isolated client class MockSummarizerModel {
    *ModelProvider;

    final readonly & ChatAssistantMessage memorySummaryMessage;

    isolated function init(readonly & ChatAssistantMessage memorySummaryMessage) {
        self.memorySummaryMessage = memorySummaryMessage;
    }

    isolated remote function chat(
            ChatMessage[]|ChatUserMessage messages, 
            ChatCompletionFunctions[] tools, string? stop) returns ChatAssistantMessage|Error => 
                self.memorySummaryMessage;

    isolated remote function generate(Prompt prompt, typedesc<anydata> td) returns td|Error = external;
}
