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

@test:Config {}
function testTextDataLoaderLoadPdf() returns error? {
    // Test PDF loading with a sample PDF file
    string pdfPath = "tests/resources/data-loader/Operating_Systems_From_0_to_1.pdf";
    TextDataLoader loader = new (pdfPath);

    Document[]|Document|Error result = loader.load();

    // Verify the result is not an error
    if result is Error {
        test:assertFail("PDF loading failed: " + result.message());
    }

    // Handle both single document and array of documents
    Document document;
    if result is Document[] {
        test:assertEquals(result.length(), 1, "Should return array with single document");
        document = result[0];
    } else {
        document = result;
    }

    // Validate document type
    test:assertEquals(document.'type, "text", "Document type should be 'text'");

    // Validate metadata exists and has expected fields
    Metadata? metadata = document.metadata;
    if metadata is () {
        test:assertFail("Document metadata should not be null");
    }

    // Validate mime type
    string? mimeType = metadata.mimeType;
    if mimeType is () {
        test:assertFail("Document mime type should not be null");
    }
    test:assertEquals(mimeType, "application/pdf", "MIME type should be 'application/pdf'");

    // Validate file extension
    string? fileName = metadata.fileName;
    if fileName is () {
        test:assertFail("Document file name should not be null");
    }
    test:assertTrue(fileName.endsWith(".pdf"), "File name should end with .pdf");

    // Validate content is not empty
    anydata content = document.content;
    if content is string {
        test:assertTrue(content.length() > 0, "Document content should not be empty");
    } else {
        test:assertFail("Document content should be a string");
    }
}

@test:Config {}
function testTextDataLoaderUnsupportedFileType() returns error? {
    // Test with an unsupported file type
    string unsupportedPath = "tests/resources/data-loader/test.txt";
    TextDataLoader loader = new (unsupportedPath);

    Document[]|Document|Error result = loader.load();

    // Verify the result is an error for unsupported file types
    if result is Error {
        test:assertEquals(result.message(), "Unsupported file type",
            "Should return error for unsupported file types");
    } else {
        test:assertFail("Should return error for unsupported file types");
    }
}
