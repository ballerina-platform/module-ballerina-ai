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
