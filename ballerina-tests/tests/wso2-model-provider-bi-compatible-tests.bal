// Copyright (c) 2025 WSO2 LLC. (http://www.wso2.org).
//
// WSO2 Inc. licenses this file to you under the Apache License,
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
function testGenerateApiWithBasicReturnType() returns error? {
    int|error rating = defaultModelProvider->generate(`Rate this blog out of 10.
        Title: ${blog1.title}
        Content: ${blog1.content}`);
    test:assertEquals(rating, 4);
}

@test:Config
function testGenerateApiWithBasicArrayReturnType() returns error? {
    int[]|error rating = defaultModelProvider->generate(`Evaluate this blogs out of 10.
        Title: ${blog1.title}
        Content: ${blog1.content}

        Title: ${blog1.title}
        Content: ${blog1.content}`);
    test:assertEquals(rating, [9, 1]);
}

@test:Config
function testGenerateApiWithRecordReturnType() returns error? {
    Review|error result = defaultModelProvider->generate(`Please rate this blog out of ${"10"}.
        Title: ${blog2.title}
        Content: ${blog2.content}`);
    test:assertEquals(result, check review.fromJsonStringWithType(Review));
}

@test:Config
function testGenerateApiWithRecordArrayReturnType() returns error? {
    int maxScore = 10;
    Review r = check review.fromJsonStringWithType(Review);

    ReviewArray|error result = defaultModelProvider->generate(`Please rate this blogs out of ${maxScore}.
        [{Title: ${blog1.title}, Content: ${blog1.content}}, {Title: ${blog2.title}, Content: ${blog2.content}}]`);
    test:assertEquals(result, [r, r]);
}

@test:Config
function testGenerateApiWithInvalidBasicType() returns error? {
    boolean|error rating = defaultModelProvider->generate(`What is ${1} + ${1}?`);
    test:assertTrue(rating is error);
    test:assertTrue((<error>rating).message().includes(ERROR_MESSAGE));
}

@test:Config
function testGenerateApiWithInvalidMapType() returns error? {
    map<string>|error rating = trap defaultModelProvider->generate(
                `Tell me name and the age of the top 10 world class cricketers`);
    string msg = (<error>rating).message();
    test:assertTrue(rating is error);
    test:assertTrue(msg.includes(RUNTIME_SCHEMA_NOT_SUPPORTED_ERROR_MESSAGE),
        string `expected error message to contain: ${RUNTIME_SCHEMA_NOT_SUPPORTED_ERROR_MESSAGE}, but found ${msg}`);
}

@test:Config
function testGenerateApiWithInvalidRecordArrayType2() returns error? {
    ProductNameArray|error rating = defaultModelProvider->generate(
                `Tell me name and the age of the top 10 world class cricketers`);
    test:assertTrue(rating is error);
    test:assertTrue((<error>rating).message().includes(ERROR_MESSAGE));
}

@test:Config
function testGenerateApiWithStringUnionNull() returns error? {
    string? result = check defaultModelProvider->generate(`Give me a random joke`);
    test:assertTrue(result is string);
}

@test:Config
function testGenerateApiWithRecUnionBasicType() returns error? {
    Cricketers|string result = check defaultModelProvider->generate(`Give me a random joke about cricketers`);
    test:assertTrue(result is string);
}

@test:Config
function testGenerateApiWithRecUnionNull() returns error? {
    Cricketers1? result = check defaultModelProvider->generate(`Name a random world class cricketer in India`);
    test:assertTrue(result is Cricketers1);
}

@test:Config
function testGenerateApiWithArrayOnly() returns error? {
    Cricketers2[] result = check defaultModelProvider->generate(`Name 10 world class cricketers in India`);
    test:assertTrue(result is Cricketers2[]);
}

@test:Config
function testGenerateApiWithArrayUnionBasicType() returns error? {
    Cricketers3[]|string result = check defaultModelProvider->generate(`Name 10 world class cricketers as string`);
    test:assertTrue(result is Cricketers3[]);
}

@test:Config
function testGenerateApiWithArrayUnionNull() returns error? {
    Cricketers4[]? result = check defaultModelProvider->generate(`Name 10 world class cricketers`);
    test:assertTrue(result is Cricketers4[]);
}

@test:Config
function testGenerateApiWithArrayUnionRecord() returns error? {
    Cricketers5[]|Cricketers6|error result = defaultModelProvider->generate(`Name top 10 world class cricketers`);
    test:assertTrue(result is Cricketers5[]);
}

@test:Config
function testGenerateApiWithArrayUnionRecord2() returns error? {
    Cricketers7[]|Cricketers8|error result = defaultModelProvider->generate(`Name a random world class cricketer`);
    test:assertTrue(result is Cricketers8);
}
