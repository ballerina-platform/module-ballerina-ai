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

import ballerina/test;

isolated function compareValuesData() returns [json, MetadataFilterOperator, json, boolean][] => [
    // EQUAL
    ["hello", EQUAL, "hello", true],
    ["hello", EQUAL, "world", false],
    [42, EQUAL, 42, true],
    [42, EQUAL, 43, false],
    [true, EQUAL, true, true],
    [true, EQUAL, false, false],
    // NOT_EQUAL
    ["hello", NOT_EQUAL, "world", true],
    ["hello", NOT_EQUAL, "hello", false],
    [1, NOT_EQUAL, 2, true],
    [1, NOT_EQUAL, 1, false],
    // IN
    ["b", IN, ["a", "b", "c"], true],
    ["d", IN, ["a", "b", "c"], false],
    [2, IN, [1, 2, 3], true],
    [5, IN, [1, 2, 3], false],
    ["a", IN, "a", false],  // non-array right operand
    // NOT_IN
    ["d", NOT_IN, ["a", "b", "c"], true],
    ["b", NOT_IN, ["a", "b", "c"], false],
    [5, NOT_IN, [1, 2, 3], true],
    [2, NOT_IN, [1, 2, 3], false],
    ["a", NOT_IN, "a", false],  // non-array right operand
    // GREATER_THAN
    [10, GREATER_THAN, 5, true],
    [5, GREATER_THAN, 10, false],
    [5, GREATER_THAN, 5, false],
    // LESS_THAN
    [5, LESS_THAN, 10, true],
    [10, LESS_THAN, 5, false],
    [5, LESS_THAN, 5, false],
    // GREATER_THAN_OR_EQUAL
    [10, GREATER_THAN_OR_EQUAL, 5, true],
    [5, GREATER_THAN_OR_EQUAL, 5, true],
    [4, GREATER_THAN_OR_EQUAL, 5, false],
    // LESS_THAN_OR_EQUAL
    [5, LESS_THAN_OR_EQUAL, 10, true],
    [5, LESS_THAN_OR_EQUAL, 5, true],
    [10, LESS_THAN_OR_EQUAL, 5, false]
];

@test:Config {
    dataProvider: compareValuesData
}
isolated function testCompareValues(json left, MetadataFilterOperator operator, json right, boolean expected)
        returns error? {
    test:assertEquals(check compareValues(left, operator, right), expected);
}

@test:Config
isolated function testCompareValuesWithNonNumericOperandsReturnsError() {
    boolean|error result = compareValues("abc", GREATER_THAN, "def");
    test:assertTrue(result is error);
}
