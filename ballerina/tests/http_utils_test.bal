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

import ballerina/http;
import ballerina/mime;
import ballerina/test;

isolated function serializedArrayData() returns [string, anydata[], string, boolean, string][] => [
    // FORM + !explode  →  key=val1,val2
    [
        "tags",
        ["a", "b"],
        FORM,
        false,
        "tags=a,b"
    ],
    // SPACEDELIMITED + !explode  →  key=val1%20val2
    [
        "tags",
        ["a", "b"],
        SPACEDELIMITED,
        false,
        "tags=a%20b"
    ],
    // PIPEDELIMITED + !explode  →  key=val1|val2
    [
        "tags",
        ["a", "b"],
        PIPEDELIMITED,
        false,
        "tags=a|b"
    ],
    // DEEPOBJECT  →  key[]=val1&key[]=val2
    [
        "tags",
        ["a", "b"],
        DEEPOBJECT,
        true,
        "tags[]=a&tags[]=b"
    ],
    // default (FORM + explode=true)  →  key=val1&key=val2
    [
        "tags",
        ["a", "b"],
        FORM,
        true,
        "tags=a&tags=b"
    ],
    // empty array  →  ""
    [
        "tags",
        [],
        FORM,
        true,
        ""
    ]
];

@test:Config {
    dataProvider: serializedArrayData,
    groups: ["http-utils", "getSerializedArray"]
}
isolated function testGetSerializedArray(string arrayName, anydata[] anyArray, string style, boolean explode,
        string expected) {
    test:assertEquals(getSerializedArray(arrayName, anyArray, style, explode), expected);
}

@test:Config {
    groups: ["http-utils", "getDeepObjectStyleRequest"]
}
isolated function testGetDeepObjectStyleRequestWithPrimitiveField() {
    test:assertEquals(getDeepObjectStyleRequest("p", {"name": "alice"}), "p[name]=alice");
}

@test:Config {
    groups: ["http-utils", "getDeepObjectStyleRequest"]
}
isolated function testGetDeepObjectStyleRequestWithPrimitiveArrayField() {
    // A named concrete record preserves the string[] runtime type tag on the field.
    record {string[] tags;} r = {tags: ["a", "b"]};
    test:assertEquals(getDeepObjectStyleRequest("p", r), "p[tags][][]=a&p[tags][][]=b");
}

@test:Config {
    groups: ["http-utils", "getDeepObjectStyleRequest"]
}
isolated function testGetDeepObjectStyleRequestWithNestedRecordField() {
    test:assertEquals(getDeepObjectStyleRequest("p", {"addr": {"city": "London"}}), "p[addr][city]=London");
}

@test:Config {
    groups: ["http-utils", "getDeepObjectStyleRequest"]
}
isolated function testGetDeepObjectStyleRequestWithRecordArrayField() {
    // A named concrete record preserves the record{}[] runtime type tag on the field.
    record {int id;} r1 = {id: 1};
    record {int id;} r2 = {id: 2};
    record {record {int id;}[] items;} r = {items: [r1, r2]};
    test:assertEquals(getDeepObjectStyleRequest("p", r), "p[items][0][id]=1&p[items][1][id]=2");
}

@test:Config {
    groups: ["http-utils", "getDeepObjectStyleRequest"]
}
isolated function testGetDeepObjectStyleRequestWithEmptyRecord() {
    test:assertEquals(getDeepObjectStyleRequest("p", {}), "");
}

isolated function formStyleData() returns [string, record {}, boolean, string][] {
    record {} nested = {"addr": {"city": "London"}};
    return [
        // explode=true — PrimitiveType field
        [
            "p",
            {"name": "alice"},
            true,
            "name=alice"
        ],
        // explode=true — nested record {} (recursive)
        [
            "p",
            nested,
            true,
            "city=London"
        ],
        // explode=true — empty record
        [
            "p",
            {},
            true,
            ""
        ],
        // explode=false — PrimitiveType field
        [
            "p",
            {"name": "alice"},
            false,
            "name,alice"
        ],
        // explode=false — nested record {} (recursive)
        [
            "p",
            nested,
            false,
            "city,London"
        ]
    ];
}

@test:Config {
    dataProvider: formStyleData,
    groups: ["http-utils", "getFormStyleRequest"]
}
isolated function testGetFormStyleRequest(string parent, record {} anyRecord, boolean explode, string expected) {
    test:assertEquals(getFormStyleRequest(parent, anyRecord, explode), expected);
}

// PrimitiveType[] cases require a typed concrete record so string[] runtime tag is preserved.
@test:Config {
    groups: ["http-utils", "getFormStyleRequest"]
}
isolated function testGetFormStyleRequestExplodeTrueWithPrimitiveArrayField() {
    record {string[] tags;} r = {tags: ["a", "b"]};
    test:assertEquals(getFormStyleRequest("p", r), "tags=a&tags=b");
}

@test:Config {
    groups: ["http-utils", "getFormStyleRequest"]
}
isolated function testGetFormStyleRequestExplodeFalseWithPrimitiveArrayField() {
    record {string[] tags;} r = {tags: ["a", "b"]};
    test:assertEquals(getFormStyleRequest("p", r, false), "tags=a,b");
}

isolated function serializedRecordArrayData() returns [string, record {}[], string, boolean, string][] => [
    // DEEPOBJECT — indexed parent keys
    [
        "p",
        [{"name": "alice"}, {"name": "bob"}],
        DEEPOBJECT,
        true,
        "p[0][name]=alice&p[1][name]=bob"
    ],
    // FORM + explode=true — comma-separated form-encoded records
    [
        "p",
        [{"name": "alice"}, {"name": "bob"}],
        FORM,
        true,
        "name=alice,name=bob"
    ],
    // FORM + explode=false — prefixed with parent=
    [
        "p",
        [{"name": "alice"}],
        FORM,
        false,
        "p=name,alice"
    ],
    // empty array
    [
        "p",
        [],
        FORM,
        true,
        ""
    ]
];

@test:Config {
    dataProvider: serializedRecordArrayData,
    groups: ["http-utils", "getSerializedRecordArray"]
}
isolated function testGetSerializedRecordArray(string parent, record {}[] value, string style, boolean explode,
        string expected) {
    test:assertEquals(getSerializedRecordArray(parent, value, style, explode), expected);
}

@test:Config {
    groups: ["http-utils", "getPathForQueryParam"]
}
isolated function testGetPathForQueryParamWithPrimitiveArray() {
    // A typed variable preserves the string[] runtime type tag for the is PrimitiveType[] check.
    string[] tags = ["a", "b"];
    string result = getPathForQueryParam({"tags": tags}, {"tags": {style: FORM, explode: false}});
    test:assertEquals(result, "?tags=a,b");
}

@test:Config {
    groups: ["http-utils", "getPathForQueryParam"]
}
isolated function testGetPathForQueryParamWithRecordDeepObject() {
    string result = getPathForQueryParam({"filter": {name: "alice"}}, {"filter": {style: DEEPOBJECT, explode: true}});
    test:assertEquals(result, "?filter[name]=alice");
}

@test:Config {
    groups: ["http-utils", "getPathForQueryParam"]
}
isolated function testGetPathForQueryParamWithRecordFormStyle() {
    string result = getPathForQueryParam({"filter": {name: "alice"}}, {"filter": {style: FORM, explode: true}});
    test:assertEquals(result, "?name=alice");
}

@test:Config {
    groups: ["http-utils", "getPathForQueryParam"]
}
isolated function testGetPathForQueryParamElseBranch() {
    // int[][] is not PrimitiveType, not PrimitiveType[], not record{} → falls to else branch
    int[][] matrix = [[1, 2], [3, 4]];
    map<anydata> queryParam = {"matrix": matrix};
    string result = getPathForQueryParam(queryParam);
    test:assertEquals(result, "?matrix=" + matrix.toString());
}

isolated function simpleStyleParamsPrimitiveData() returns [string, json, string][] => [
    // PrimitiveType (string)
    [
        "k",
        "hello",
        "hello"
    ],
    // PrimitiveType (int)
    [
        "k",
        42,
        "42"
    ]
];

@test:Config {
    dataProvider: simpleStyleParamsPrimitiveData,
    groups: ["http-utils", "getSimpleStyleParams"]
}
isolated function testGetSimpleStyleParamsPrimitive(string key, json paramValue, string expected) returns error? {
    test:assertEquals(check getSimpleStyleParams(key, paramValue), expected);
}

// PrimitiveType[] and map<PrimitiveType> paths need typed variables to preserve
// the specific runtime type tag so the is-checks inside the function succeed.
@test:Config {
    groups: ["http-utils", "getSimpleStyleParams"]
}
isolated function testGetSimpleStyleParamsWithPrimitiveArray() returns error? {
    int[] arr = [1, 2, 3];
    test:assertEquals(check getSimpleStyleParams("k", arr), "1,2,3");
}

@test:Config {
    groups: ["http-utils", "getSimpleStyleParams"]
}
isolated function testGetSimpleStyleParamsWithMapOfPrimitives() returns error? {
    map<int|string> m = {a: 1, b: "hi"};
    test:assertEquals(check getSimpleStyleParams("k", m), "a,1,b,hi");
}

@test:Config {
    groups: ["http-utils", "getSimpleStyleParams"]
}
isolated function testGetSimpleStyleParamsUnsupportedType() {
    // Nested array — not PrimitiveType, not PrimitiveType[], not map<PrimitiveType> → error
    string|UnsupportedSerializationError result = getSimpleStyleParams("k", [[1, 2]]);
    test:assertTrue(result is UnsupportedSerializationError);
    if result is UnsupportedSerializationError {
        test:assertTrue(result.message().includes("Unsupported value for path paremeter serialization."));
    }
}

@test:Config {
    groups: ["http-utils", "getContentLength"]
}
function testGetContentLengthWithMissingHeader() {
    http:Response response = new;
    int|error? result = getContentLength(response);
    test:assertTrue(result is ());
}

@test:Config {
    groups: ["http-utils", "getContentLength"]
}
function testGetContentLengthWithValidHeader() {
    http:Response response = new;
    response.setHeader(mime:CONTENT_LENGTH, "42");
    int|error? result = getContentLength(response);
    test:assertEquals(result, 42);
}

@test:Config {
    groups: ["http-utils", "getContentLength"]
}
function testGetContentLengthWithInvalidHeader() {
    // int:fromString returns an error for non-numeric strings
    http:Response response = new;
    response.setHeader(mime:CONTENT_LENGTH, "not-a-number");
    int|error? result = getContentLength(response);
    test:assertTrue(result is error);
}

@test:Config {
    groups: ["http-utils", "getRequestMessage"]
}
function testGetRequestMessageWithXmlMediaType() returns error? {
    HttpInput httpInput = {path: "/test", requestBody: {name: "test"}};
    json|xml|error result = getRequestMessage("application/xml", httpInput);
    test:assertTrue(result is xml);
}

@test:Config {
    groups: ["http-utils", "getRequestMessage"]
}
function testGetRequestMessageWithJsonMediaType() {
    HttpInput httpInput = {path: "/test", requestBody: {name: "test"}};
    json|xml|error result = getRequestMessage("application/json", httpInput);
    test:assertEquals(result, {name: "test"});
}

@test:Config {
    groups: ["http-utils", "getRequestMessage"]
}
function testGetRequestMessageWithNilMediaType() {
    HttpInput httpInput = {path: "/test", requestBody: {name: "test"}};
    json|xml|error result = getRequestMessage((), httpInput);
    test:assertEquals(result, {name: "test"});
}
