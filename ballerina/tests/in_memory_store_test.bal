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

    ChatInteractiveMessage[]|MemoryError messages = store.get("key1");
    if messages is MemoryError {
        test:assertFail("Expected 'ChatInteractiveMessage[]' but found 'MemoryError'");
    }
    test:assertEquals(messages.length(), 0);

    check store.put("key1", {role: USER, content: "Hello"});

    messages = store.get("key2");
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
    MemoryError? err = store.remove(K1, count);

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
