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

@test:Config {
    dataProvider: invalidMemoryStoreSizes
}
function testInMemoryShortTermMemoryStoreInitWithInvalidSize(int size) returns error? {
    InMemoryShortTermMemoryStore|MemoryError store = new (size);

    if store is InMemoryShortTermMemoryStore {
        test:assertFail("Expected 'MemoryError' but found 'InMemoryShortTermMemoryStore'");
    }

    test:assertEquals(store.message(), 
        "Failed to initialize in-memory short term memory store: Size must be at least 3");
}

isolated function invalidMemoryStoreSizes() returns int[][] => [
    [-1], [0], [2]
];

@test:Config
function testInMemoryShortTermMemoryStoreRetrievalWithNoMessages() returns error? {
    InMemoryShortTermMemoryStore store = check new (4);

    ChatInteractiveMessage[]|MemoryError messages = store.getChatInteractiveMessages("key1");
    if messages is MemoryError {
        test:assertFail("Expected 'ChatInteractiveMessage[]' but found 'MemoryError'");
    }
    test:assertEquals(messages.length(), 0);

    check store.put("key1", {role: USER, content: "Hello"});

    messages = store.getChatInteractiveMessages("key2");
    if messages is MemoryError {
        test:assertFail("Expected 'ChatInteractiveMessage[]' but found 'MemoryError'");
    }
    test:assertEquals(messages.length(), 0);
}

@test:Config {
    dataProvider: invalidMemoryStoreRemovalCounts
}
function testInMemoryShortTermMemoryStoreRemovalWithInvalidCount(InMemoryShortTermMemoryStore store, int count) 
        returns error? {
    MemoryError? err = store.removeChatInteractiveMessages(K1, count);

    if err is () {
        test:assertFail("Expected 'MemoryError' but found '()'");
    }

    test:assertEquals(err.message(), "Count to remove must be nil or a positive integer.");
}

isolated function invalidMemoryStoreRemovalCounts() returns [InMemoryShortTermMemoryStore, int][]|error {
    InMemoryShortTermMemoryStore store1 = check new (4);
    check store1.put(K1, {role: USER, content: "Hello"});

    InMemoryShortTermMemoryStore store2 = check new (4);

    return [
        [store1, -1],
        [store1, 0],
        [store2, -10]
    ];
}

@test:Config
function testInMemoryShortTermMemoryStoreGetMethodsWithSystemMessage() returns error? {
    ShortTermMemoryStore store = check new InMemoryShortTermMemoryStore(5);

    final string k = "testKey";

    ChatSystemMessage ksm1 = {role: SYSTEM, content: "System message"};
    ChatUserMessage km1 = {role: USER, content: "User message 1"};
    ChatAssistantMessage km2 = {role: ASSISTANT, content: "Assistant message 1"};
    ChatUserMessage km3 = {role: USER, content: "User message 2"};

    check store.put(k, ksm1);
    check store.put(k, km1);
    check store.put(k, km2);
    check store.put(k, km3);
    
    ChatSystemMessage? res = check store.getChatSystemMessage(k);
    if res is () {
        test:assertFail("Expected 'ChatSystemMessage' but found '()'");
    }
    assertChatMessageEquals(res, ksm1);

    ChatInteractiveMessage[] interactiveMessages = check store.getChatInteractiveMessages(k);
    test:assertEquals(interactiveMessages.length(), 3);
    assertChatMessageEquals(interactiveMessages[0], km1);
    assertChatMessageEquals(interactiveMessages[1], km2);
    assertChatMessageEquals(interactiveMessages[2], km3);

    var allMessages = check store.getAll(k);
    if allMessages !is [ChatSystemMessage, ChatInteractiveMessage...] {
        test:assertFail("Expected '[ChatSystemMessage, ChatInteractiveMessage...]' but found 'ChatInteractiveMessage[]'");
    }
    test:assertEquals(allMessages.length(), 4);
    assertChatMessageEquals(allMessages[0], ksm1);
    assertChatMessageEquals(allMessages[1], km1);
    assertChatMessageEquals(allMessages[2], km2);
    assertChatMessageEquals(allMessages[3], km3);
}

@test:Config
function testInMemoryShortTermMemoryStoreGetMethodsWithoutSystemMessage() returns error? {
    ShortTermMemoryStore store = check new InMemoryShortTermMemoryStore(5);

    final string k = "testKey";

    ChatUserMessage km1 = {role: USER, content: "User message 1"};
    ChatAssistantMessage km2 = {role: ASSISTANT, content: "Assistant message 1"};
    ChatUserMessage km3 = {role: USER, content: "User message 2"};

    check store.put(k, km1);
    check store.put(k, km2);
    check store.put(k, km3);

    ChatSystemMessage? res = check store.getChatSystemMessage(k);
    test:assertEquals(res, ());

    ChatInteractiveMessage[] interactiveMessages = check store.getChatInteractiveMessages(k);
    test:assertEquals(interactiveMessages.length(), 3);
    assertChatMessageEquals(interactiveMessages[0], km1);
    assertChatMessageEquals(interactiveMessages[1], km2);
    assertChatMessageEquals(interactiveMessages[2], km3);

    var allMessages = check store.getAll(k);
    if allMessages !is ChatInteractiveMessage[] {
        test:assertFail("Expected 'ChatInteractiveMessage[]' but found '[ChatSystemMessage, ChatInteractiveMessage...]'");
    }
    test:assertEquals(allMessages.length(), 3);
    assertChatMessageEquals(allMessages[0], km1);
    assertChatMessageEquals(allMessages[1], km2);
    assertChatMessageEquals(allMessages[2], km3);
}

@test:Config
function testInMemoryShortTermMemoryStoreRemoveSystemMessage() returns error? {
    ShortTermMemoryStore store1 = check new InMemoryShortTermMemoryStore(5);
    check store1.put(K1, K1SM1);
    check store1.put(K1, K1M1);
    check store1.put(K1, k1m2);
    check store1.put(K1, K1M3);
    
    ChatSystemMessage? systemMessage1 = check store1.getChatSystemMessage(K1);
    if systemMessage1 is () {
        test:assertFail("Expected 'ChatSystemMessage' but found '()'");
    }
    check store1.removeChatSystemMessage(K1);
    systemMessage1 = check store1.getChatSystemMessage(K1);
    if systemMessage1 !is () {
        test:assertFail("Expected '()' but found 'ChatSystemMessage'");
    }

    ChatInteractiveMessage[] interactiveMessages1 = check store1.getChatInteractiveMessages(K1);
    test:assertEquals(interactiveMessages1.length(), 3);
    
    ShortTermMemoryStore store2 = check new InMemoryShortTermMemoryStore(5);
    check store2.put(K1, K1M1);
    check store2.put(K1, k1m2);
    
    ChatSystemMessage? systemMessage2 = check store2.getChatSystemMessage(K1);
    if systemMessage2 !is () {
        test:assertFail("Expected '()' but found 'ChatSystemMessage'");
    }
    MemoryError? removeStatus = store2.removeChatSystemMessage(K1);
    test:assertEquals(removeStatus, ());

    ChatInteractiveMessage[] interactiveMessages2 = check store2.getChatInteractiveMessages(K1);
    test:assertEquals(interactiveMessages2.length(), 2);
}

@test:Config
function testInMemoryShortTermMemoryStoreRemoveInteractiveMessages() returns error? {
    ShortTermMemoryStore store1 = check new InMemoryShortTermMemoryStore(5);
    check store1.put(K1, K1M1);
    check store1.put(K1, k1m2);
    check store1.put(K1, K1SM1);
    check store1.put(K1, K1M3);
    check store1.put(K1, K1M4);
    
    test:assertTrue(store1.getChatSystemMessage(K1) is ChatSystemMessage);
    test:assertEquals((check store1.getChatInteractiveMessages(K1)).length(), 4);

    check store1.removeChatInteractiveMessages(K1, 2);
    test:assertTrue(store1.getChatSystemMessage(K1) is ChatSystemMessage);
    ChatInteractiveMessage[] interactiveMessages1 = check store1.getChatInteractiveMessages(K1);
    test:assertEquals(interactiveMessages1.length(), 2);
    assertChatMessageEquals(interactiveMessages1[0], K1M3);
    assertChatMessageEquals(interactiveMessages1[1], K1M4);

    check store1.removeChatInteractiveMessages(K1);
    test:assertTrue(store1.getChatSystemMessage(K1) is ChatSystemMessage);
    test:assertEquals((check store1.getChatInteractiveMessages(K1)).length(), 0);

    ShortTermMemoryStore store2 = check new InMemoryShortTermMemoryStore(5);
    check store2.put(K1, K1M1);
    check store2.put(K1, k1m2);
    
    test:assertTrue(store2.getChatSystemMessage(K1) is ());
    test:assertEquals((check store2.getChatInteractiveMessages(K1)).length(), 2);
    check store2.removeChatInteractiveMessages(K1);
    test:assertTrue(store2.getChatSystemMessage(K1) is ());
    test:assertEquals((check store2.getChatInteractiveMessages(K1)).length(), 0);
}


@test:Config
function testInMemoryShortTermMemoryStoreRemoveAll() returns error? {
    ShortTermMemoryStore store = check new InMemoryShortTermMemoryStore(5);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);
    check store.put(K1, K1SM1);
    check store.put(K1, K1M3);
    check store.put(K1, K1M4);
    
    test:assertTrue(store.getChatSystemMessage(K1) is ChatSystemMessage);
    test:assertEquals((check store.getChatInteractiveMessages(K1)).length(), 4);

    check store.removeAll(K1);
    test:assertTrue(store.getChatSystemMessage(K1) is ());
    test:assertEquals((check store.getChatInteractiveMessages(K1)).length(), 0);

    ShortTermMemoryStore storeWithOnlySystemMessage = check new InMemoryShortTermMemoryStore(5);
    check storeWithOnlySystemMessage.put(K1, K1SM1);
    
    test:assertTrue(storeWithOnlySystemMessage.getChatSystemMessage(K1) is ChatSystemMessage);
    test:assertEquals((check storeWithOnlySystemMessage.getChatInteractiveMessages(K1)).length(), 0);

    check storeWithOnlySystemMessage.removeAll(K1);
    test:assertTrue(storeWithOnlySystemMessage.getChatSystemMessage(K1) is ());
    test:assertEquals((check storeWithOnlySystemMessage.getChatInteractiveMessages(K1)).length(), 0);

    ShortTermMemoryStore storeWithOnlyInteractiveMessages = check new InMemoryShortTermMemoryStore(5);
    check storeWithOnlyInteractiveMessages.put(K1, K1M1);
    check storeWithOnlyInteractiveMessages.put(K1, k1m2);
    
    test:assertTrue(storeWithOnlyInteractiveMessages.getChatSystemMessage(K1) is ());
    test:assertEquals((check storeWithOnlyInteractiveMessages.getChatInteractiveMessages(K1)).length(), 2);

    check storeWithOnlyInteractiveMessages.removeAll(K1);
    test:assertTrue(storeWithOnlyInteractiveMessages.getChatSystemMessage(K1) is ());
    test:assertEquals((check storeWithOnlyInteractiveMessages.getChatInteractiveMessages(K1)).length(), 0);
}
