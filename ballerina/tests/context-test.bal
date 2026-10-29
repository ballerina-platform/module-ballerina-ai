// Copyright (c) 2025 WSO2 LLC. (http://www.wso2.com).
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

@test:Config
isolated function testContext() returns error? {
    Context ctx = new;
    ctx.set("key1", "value1");
    ctx.set("key2", 123);
    ctx.set("key3", true);

    string[] keys = ctx.keys();
    test:assertEquals(keys, ["key1", "key2", "key3"]);

    test:assertEquals(ctx.get("key1"), "value1");

    ctx.set("key1", "overwrittenValue");
    test:assertEquals(ctx.get("key1"), "overwrittenValue");

    int value2 = check ctx.getWithType("key2");
    test:assertEquals(value2, 123);

    boolean value3 = check ctx.getWithType("key3");
    test:assertTrue(value3);

    ctx.remove("key1");
    test:assertEquals(ctx.hasKey("key1"), false);
}

@test:Config
isolated function testContextGetWithTypeReturnsACopy() returns error? {
    Context ctx = new;
    int[] initialItems = [1, 2];
    ctx.set("items", initialItems);

    int[] items = check ctx.getWithType("items");
    items.push(3);

    int[] storedItems = check ctx.getWithType("items");
    test:assertEquals(storedItems, [1, 2], "Mutating a value from getWithType must not change the context");
}

@test:Config
isolated function testContextGetWithTypeErrors() {
    Context ctx = new;
    ctx.set("count", 1);

    string|Error missing = ctx.getWithType("unknown");
    if missing !is Error {
        test:assertFail("Expected an error for a missing key");
    }
    test:assertEquals(missing.message(), "no member found for key: unknown");

    string|Error wrongType = ctx.getWithType("count");
    if wrongType !is Error {
        test:assertFail("Expected an error for a value of a different type");
    }
    test:assertEquals(wrongType.message(), "type conversion failed for value of key: count");
}
