// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
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

final int[] intArray = [];
final json[] jsonArray = [];
final string[] stringArray = [];
final boolean[] boolArray = [];
final float[] floatArray = [];

function isSimpleTypeData() returns [typedesc<json>, boolean][] => [
    [string, true],
    [int, true],
    [float, true],
    [decimal, true],
    [boolean, true],
    [typeof intArray, false],
    [typeof jsonArray, false],
    [typeof stringArray, false]
];

@test:Config {
    dataProvider: isSimpleTypeData,
    groups: ["json-schema", "isSimpleType"]
}
function testIsSimpleType(typedesc<json> td, boolean expected) {
    test:assertEquals(isSimpleType(td), expected);
}

isolated function getStringRepresentationData() returns [typedesc<json>, string][] => [
    [string, "string"],
    [int, "integer"],
    [float, "number"],
    [decimal, "number"],
    [boolean, "boolean"]
];

@test:Config {
    dataProvider: getStringRepresentationData,
    groups: ["json-schema", "getStringRepresentation"]
}
function testGetStringRepresentation(typedesc<json> td, string expected) {
    test:assertEquals(getStringRepresentation(td), expected);
}

isolated function containsNilData() returns [typedesc<json>, boolean][] {
    string? s = ();
    int? i = ();
    boolean? b = ();
    float? f = ();
    return [
        [string, false],
        [int, false],
        [boolean, false],
        [typeof s, true],
        [typeof i, true],
        [typeof b, true],
        [typeof f, true]
    ];
}

@test:Config {
    dataProvider: containsNilData,
    groups: ["json-schema", "containsNil"]
}
function testContainsNil(typedesc<json> td, boolean expected) {
    test:assertEquals(containsNil(td), expected);
}

function arrayMemberTypeData() returns [typedesc<json>, string][] => [
    [typeof intArray, "integer"],
    [typeof stringArray, "string"],
    [typeof boolArray, "boolean"],
    [typeof floatArray, "number"]
];

@test:Config {
    dataProvider: arrayMemberTypeData,
    groups: ["json-schema", "getArrayMemberType"]
}
function testGetArrayMemberType(typedesc<json> inputType, string expectedTypeStr) {
    test:assertEquals(getStringRepresentation(getArrayMemberType(inputType)), expectedTypeStr);
}

isolated function simpleTypeSchemaData() returns [typedesc<json>, string][] => [
    [string, "string"],
    [int, "integer"],
    [float, "number"],
    [decimal, "number"],
    [boolean, "boolean"]
];

@test:Config {
    dataProvider: simpleTypeSchemaData,
    groups: ["json-schema", "generateJsonSchemaForTypedesc"]
}
function testGenerateJsonSchemaForSimpleType(typedesc<json> td, string expectedType) {
    JsonSchema|JsonArraySchema|map<json>|Error result = generateJsonSchemaForTypedesc(td, false);
    test:assertEquals(result, <JsonSchema>{'type: expectedType});
}

function arrayTypeSchemaData() returns [typedesc<json>, string][] => [
    [typeof intArray, "integer"],
    [typeof stringArray, "string"],
    [typeof boolArray, "boolean"],
    [typeof floatArray, "number"]
];

@test:Config {
    dataProvider: arrayTypeSchemaData,
    groups: ["json-schema", "generateJsonSchemaForTypedesc"]
}
function testGenerateJsonSchemaForArrayType(typedesc<json> td, string itemType) {
    JsonSchema|JsonArraySchema|map<json>|Error result = generateJsonSchemaForTypedesc(td, false);
    test:assertEquals(result, <JsonArraySchema>{items: {'type: itemType}});
}

function nilableArrayTypeSchemaData() returns [typedesc<json>, string][] => [
    [typeof intArray, "integer"],
    [typeof stringArray, "string"],
    [typeof boolArray, "boolean"]
];

@test:Config {
    dataProvider: nilableArrayTypeSchemaData,
    groups: ["json-schema", "generateJsonSchemaForTypedesc"]
}
function testGenerateJsonSchemaForNilableArrayType(typedesc<json> td, string baseType) {
    JsonSchema|JsonArraySchema|map<json>|Error result = generateJsonSchemaForTypedesc(td, true);
    test:assertEquals(result, <JsonArraySchema>{
                items: {
                    oneOf: [
                        {'type: baseType},
                        {'type: "null"}
                    ]
                }
            });
}

isolated function unsupportedTypeData() returns [typedesc<json>][] {
    map<json>[] arrayOfJsonMap = [];
    return [
        [json],
        [typeof arrayOfJsonMap]
    ];
}

@test:Config {
    dataProvider: unsupportedTypeData,
    groups: ["json-schema", "generateJsonSchemaForTypedesc"]
}
function testGenerateJsonSchemaForUnsupportedType(typedesc<json> td) {
    JsonSchema|JsonArraySchema|map<json>|Error result = generateJsonSchemaForTypedesc(td, false);
    test:assertTrue(result is error);
    if result is error {
        test:assertTrue(result.message().includes("Runtime schema generation is not yet supported"));
    }
}
