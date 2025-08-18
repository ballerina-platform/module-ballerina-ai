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

import ballerina/ai;
import ballerina/test;

const SERVICE_URL = "http://localhost:8080/llm/azureopenai/deployments/gpt4onew";
const API_KEY = "not-a-real-api-key";
const ERROR_MESSAGE = "Error occurred while attempting to parse the response from the LLM as the expected type. Retrying and/or validating the prompt could fix the response.";
const RUNTIME_SCHEMA_NOT_SUPPORTED_ERROR_MESSAGE = "Runtime schema generation is not yet supported";

final ai:Wso2ModelProvider defaultModelProvider = check new (SERVICE_URL, API_KEY);
final ai:Wso2ModelProvider defaultModelProviderWithRetryConfig = check new (SERVICE_URL, API_KEY, generatorConfig = {retryConfig: {count: 2, interval: 2}});
final ai:Wso2ModelProvider defaultModelProviderWithRetryConfig2 = check new (SERVICE_URL, API_KEY, generatorConfig = {retryConfig: {count: 2}});
final ai:Wso2ModelProvider defaultModelProviderWithRetryConfig3 = check new (SERVICE_URL, API_KEY, generatorConfig = {retryConfig: {count: 1}});
final ai:Wso2ModelProvider defaultModelProviderWithRetryConfig4 = check new (SERVICE_URL, API_KEY, generatorConfig = {retryConfig: {}});

@test:Config
function testGenerateMethodWithBasicReturnType() returns ai:Error? {
    int|error rating = defaultModelProvider->generate(`Rate this blog out of 10.
        Title: ${blog1.title}
        Content: ${blog1.content}`);
    test:assertEquals(rating, 4);
}

@test:Config
function testGenerateMethodWithBasicArrayReturnType() returns ai:Error? {
    int[]|error rating = defaultModelProvider->generate(`Evaluate this blogs out of 10.
        Title: ${blog1.title}
        Content: ${blog1.content}

        Title: ${blog1.title}
        Content: ${blog1.content}`);
    test:assertEquals(rating, [9, 1]);
}

@test:Config
function testGenerateMethodWithRecordReturnType() returns error? {
    Review|error result = defaultModelProvider->generate(`Please rate this blog out of ${"10"}.
        Title: ${blog2.title}
        Content: ${blog2.content}`);
    test:assertEquals(result, reviewRecord);
}

@test:Config
function testGenerateMethodWithTextDocument() returns ai:Error? {
    ai:TextDocument blog = {
        content: string `Title: ${blog1.title} Content: ${blog1.content}`
    };
    int maxScore = 10;

    int|error rating = defaultModelProvider->generate(`How would you rate this ${"blog"} content out of ${maxScore}. ${blog}.`);
    test:assertEquals(rating, 4);
}

type ReviewArray Review[];

@test:Config
function testGenerateMethodWithTextDocumentArray() returns error? {
    ai:TextDocument blog = {
        content: string `Title: ${blog1.title} Content: ${blog1.content}`
    };
    ai:TextDocument[] blogs = [blog, blog];
    int maxScore = 10;

    ReviewArray|error result = defaultModelProvider->generate(`How would you rate these text blogs out of ${maxScore}. ${blogs}. Thank you!`);
    test:assertEquals(result, [reviewRecord, reviewRecord]);
}

@test:Config
function testGenerateMethodWithImageDocumentWithBinaryData() returns ai:Error? {
    ai:ImageDocument img = {
        content: imageBinaryData
    };

    string|error description = defaultModelProvider->generate(`Describe the following image. ${img}.`);
    test:assertEquals(description, "This is a sample image description.");
}

@test:Config
function testGenerateMethodWithImageDocumentWithUrl() returns ai:Error? {
    ai:ImageDocument img = {
        content: "https://example.com/image.jpg",
        metadata: {
            mimeType: "image/jpg"
        }
    };

    string|error description = defaultModelProvider->generate(`Describe the image. ${img}.`);
    test:assertEquals(description, "This is a sample image description.");
}

@test:Config
function testGenerateMethodWithImageDocumentWithInvalidUrl() returns ai:Error? {
    ai:ImageDocument img = {
        content: "This-is-not-a-valid-url"
    };

    string|ai:Error description = defaultModelProvider->generate(`Please describe the image. ${img}.`);
    if description is string {  
        test:assertFail("Expected an error, but got a string: " + description);  
    }  

    string actualErrorMessage = description.message();
    string expectedErrorMessage = "Must be a valid URL.";
    test:assertEquals(actualErrorMessage, expectedErrorMessage, 
        string `expected '${expectedErrorMessage}', found ${actualErrorMessage}`);
}

@test:Config
function testGenerateMethodWithImageDocumentArray() returns ai:Error? {
    ai:ImageDocument img = {
        content: imageBinaryData,
        metadata: {
            mimeType: "image/png"
        }
    };
    ai:ImageDocument img2 = {
        content: "https://example.com/image.jpg"
    };

    string[]|error descriptions = defaultModelProvider->generate(
        `Describe the following ${"2"} images. ${<ai:ImageDocument[]>[img, img2]}.`);
    test:assertEquals(descriptions, ["This is a sample image description.", "This is a sample image description."]);
}

@test:Config
function testGenerateMethodWithTextAndImageDocumentArray() returns ai:Error? {
    ai:ImageDocument img = {
        content: imageBinaryData,
        metadata: {
            mimeType: "image/png"
        }
    };
    ai:TextDocument blog = {
        content: string `Title: ${blog1.title} Content: ${blog1.content}`
    };

    string[]|error descriptions = defaultModelProvider->generate(
        `Please describe the following image and the doc. ${<ai:Document[]>[img, blog]}.`);
    test:assertEquals(descriptions, ["This is a sample image description.", "This is a sample doc description."]);
}

@test:Config
function testGenerateMethodWithImageDocumentsandTextDocuments() returns ai:Error? {
    ai:ImageDocument img = {
        content: imageBinaryData,
        metadata: {
            mimeType: "image/png"
        }
    };
    ai:TextDocument blog = {
        content: string `Title: ${blog1.title} Content: ${blog1.content}`
    };

    string[]|error descriptions = defaultModelProvider->generate(
        `${"Describe"} the following ${"text"} ${"document"} and image document. ${img}${blog}`);
    test:assertEquals(descriptions, ["This is a sample image description.", "This is a sample doc description."]);
}

@test:Config
function testGenerateMethodWithUnsupportedDocument() returns ai:Error? {
    string expectedErrorMessage = "Only text and image documents are supported.";

    ai:Document doc = {
        'type: "audio",
        content: "dummy-data"
    };

    ai:FileDocument fileDoc = {
        'type: "file",
        content: "dummy-url"
    };

    ai:AudioDocument audioDoc = {
        'type: "audio",
        content: "dummy-url"
    };

    string|ai:Error description = defaultModelProvider->generate(`What is the content in this document. ${doc}.`);
    if description is string {  
        test:assertFail("Expected an error, but got a string: " + description);  
    } 

    string actualErrorMessage = description.message();
    test:assertEquals(actualErrorMessage, expectedErrorMessage,
        string `expected '${expectedErrorMessage}', found ${actualErrorMessage}`);

    description = defaultModelProvider->generate(`What is the content in this document. ${fileDoc}.`);
    if description is string {  
        test:assertFail("Expected an error, but got a string: " + description);  
    } 

    actualErrorMessage = description.message();
    test:assertEquals(actualErrorMessage, expectedErrorMessage,
        string `expected '${expectedErrorMessage}', found ${actualErrorMessage}`);

    description = defaultModelProvider->generate(`What is the content in this document. ${audioDoc}.`);
    if description is string {  
        test:assertFail("Expected an error, but got a string: " + description);  
    } 

    actualErrorMessage = description.message();
    test:assertEquals(actualErrorMessage, expectedErrorMessage,
        string `expected '${expectedErrorMessage}', found ${actualErrorMessage}`);
}

@test:Config
function testGenerateMethodWithRecordArrayReturnType() returns error? {
    int maxScore = 10;

    ReviewArray|error result = defaultModelProvider->generate(`Please rate this blogs out of ${maxScore}.
        [{Title: ${blog1.title}, Content: ${blog1.content}}, {Title: ${blog2.title}, Content: ${blog2.content}}]`);
    test:assertEquals(result, [reviewRecord, reviewRecord]);
}

@test:Config
function testGenerateMethodWithInvalidBasicType() returns error? {
    boolean|ai:Error rating = defaultModelProvider->generate(`What is ${1} + ${1}?`);
    test:assertTrue(rating is error);
    test:assertTrue((<error>rating).message().includes(ERROR_MESSAGE));
}

type ProductName record {|
    string name;
|};

@test:Config
function testGenerateMethodWithInvalidMapType() returns ai:Error? {
    map<string>|error rating = defaultModelProvider->generate(
                `Tell me name and the age of the top 10 world class cricketers`);
    string msg = (<error>rating).message();
    test:assertTrue(rating is error);
    test:assertTrue(msg.includes(RUNTIME_SCHEMA_NOT_SUPPORTED_ERROR_MESSAGE),
        string `expected error message to contain: ${RUNTIME_SCHEMA_NOT_SUPPORTED_ERROR_MESSAGE}, but found ${msg}`);
}

type ProductNameArray ProductName[];

@test:Config
function testGenerateMethodWithInvalidRecordArrayType2() returns ai:Error? {
    ProductNameArray|error rating = defaultModelProvider->generate(
                `Tell me name and the age of the top 10 world class cricketers`);
    test:assertTrue(rating is error);
    test:assertTrue((<error>rating).message().includes(ERROR_MESSAGE));
}

type Cricketers record {|
    string name;
|};

type Cricketers1 record {|
    string name;
|};

type Cricketers2 record {|
    string name;
|};

type Cricketers3 record {|
    string name;
|};

type Cricketers4 record {|
    string name;
|};

type Cricketers5 record {|
    string name;
|};

type Cricketers6 record {|
    string name;
|};

type Cricketers7 record {|
    string name;
|};

type Cricketers8 record {|
    string name;
|};

@test:Config
function testGenerateMethodWithStringUnionNull() returns error? {
    string? result = check defaultModelProvider->generate(`Give me a random joke`);
    test:assertTrue(result is string);
}

@test:Config
function testGenerateMethodWithRecUnionBasicType() returns error? {
    Cricketers|string result = check defaultModelProvider->generate(`Give me a random joke about cricketers`);
    test:assertTrue(result is string);
}

@test:Config
function testGenerateMethodWithRecUnionNull() returns error? {
    Cricketers1? result = check defaultModelProvider->generate(`Name a random world class cricketer in India`);
    test:assertTrue(result is Cricketers1);
}

@test:Config
function testGenerateMethodWithArrayOnly() returns error? {
    Cricketers2[] result = check defaultModelProvider->generate(`Name 10 world class cricketers in India`);
    test:assertTrue(result is Cricketers2[]);
}

@test:Config
function testGenerateMethodWithArrayUnionBasicType() returns error? {
    Cricketers3[]|string result = check defaultModelProvider->generate(`Name 10 world class cricketers as string`);
    test:assertTrue(result is Cricketers3[]);
}

@test:Config
function testGenerateMethodWithArrayUnionNull() returns error? {
    Cricketers4[]? result = check defaultModelProvider->generate(`Name 10 world class cricketers`);
    test:assertTrue(result is Cricketers4[]);
}

@test:Config
function testGenerateMethodWithArrayUnionRecord() returns ai:Error? {
    Cricketers5[]|Cricketers6|error result = defaultModelProvider->generate(`Name top 10 world class cricketers`);
    test:assertTrue(result is Cricketers5[]);
}

@test:Config
function testGenerateMethodWithArrayUnionRecord2() returns ai:Error? {
    Cricketers7[]|Cricketers8|error result = defaultModelProvider->generate(`Name a random world class cricketer`);
    test:assertTrue(result is Cricketers8);
}

@test:Config
function testRetryImplementationInGenerateMethodWithInvalidBasicType() returns error? {
    int|ai:Error rating = defaultModelProviderWithRetryConfig->generate(`What is the result of ${1} + ${1}?`);
    test:assertEquals(rating, 2);

    rating = defaultModelProviderWithRetryConfig2->generate(`What is the result of 1 + 2?`);
    test:assertEquals(rating, 3);

    rating = defaultModelProviderWithRetryConfig3->generate(`What is the result of 1 + 3?`);
    test:assertEquals(rating, 4);

    rating = defaultModelProviderWithRetryConfig4->generate(`What is the result of 1 + 4?`);
    test:assertEquals(rating, 5);

    rating = defaultModelProviderWithRetryConfig->generate(`What is the result of ${1} + ${5}?`);
    test:assertEquals(rating, 6);

    rating = defaultModelProviderWithRetryConfig->generate(`What is the result of ${1} + ${6}?`);
    test:assertEquals(rating, 7);
}
