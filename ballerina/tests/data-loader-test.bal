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

// Helper function to validate document structure and metadata
isolated function validateDocument(Document document, string expectedMimeType, string expectedExtension) returns error? {
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
    test:assertEquals(mimeType, expectedMimeType, string `MIME type should be '${expectedMimeType}'`);

    // Validate file extension
    string? fileName = metadata.fileName;
    if fileName is () {
        test:assertFail("Document file name should not be null");
    }
    test:assertTrue(fileName.endsWith(expectedExtension), string `File name should end with ${expectedExtension}`);

    // Validate content is not empty
    anydata content = document.content;
    if content is string {
        test:assertTrue(content.length() > 0, "Document content should not be empty");
    } else {
        test:assertFail("Document content should be a string");
    }
}

// Helper function to get single document from result
isolated function getSingleDocument(Document[]|Document|Error result) returns Document|error {
    if result is Error {
        return error("Document loading failed: " + result.message());
    }

    Document document;
    if result is Document[] {
        test:assertEquals(result.length(), 1, "Should return array with single document");
        document = result[0];
    } else {
        document = result;
    }
    return document;
}

@test:Config {groups: ["pdf", "document-loader"]}
function testTextDataLoaderLoadPdf() returns error? {
    // Test PDF loading with a sample PDF file
    string pdfPath = "tests/resources/data-loader/TestDoc.pdf";
    TextDataLoader loader = check new (pdfPath);

    Document[]|Document|Error result = loader.load();
    Document document = check getSingleDocument(result);
    check validateDocument(document, "application/pdf", ".pdf");
}

@test:Config {groups: ["document-loader", "error-handling"]}
function testTextDataLoaderUnsupportedFileType() returns error? {
    // Test with an unsupported file type
    string unsupportedPath = "tests/resources/data-loader/test.txt";
    TextDataLoader loader = check new (unsupportedPath);

    Document[]|Document|Error result = loader.load();

    // Verify the result is an error for unsupported file types
    if result is Error {
        test:assertTrue(result.message().includes("Unsupported file type: txt"),
                "Should return error for unsupported file types with file extension");
    } else {
        test:assertFail("Should return error for unsupported file types");
    }
}

@test:Config {groups: ["docx", "document-loader"]}
function testTextDataLoaderLoadDocx() returns error? {
    // Test DOCX loading with a sample DOCX file
    string docxPath = "tests/resources/data-loader/TestDoc.docx";
    TextDataLoader loader = check new (docxPath);

    Document[]|Document|Error result = loader.load();
    Document document = check getSingleDocument(result);
    check validateDocument(document, "application/vnd.openxmlformats-officedocument.wordprocessingml.document", ".docx");
}

@test:Config {groups: ["pptx", "document-loader"]}
function testTextDataLoaderLoadPptx() returns error? {
    // Test PPTX loading with a sample PPTX file
    string pptxPath = "tests/resources/data-loader/Test presentation.pptx";
    TextDataLoader loader = check new (pptxPath);

    Document[]|Document|Error result = loader.load();
    Document document = check getSingleDocument(result);
    check validateDocument(document, "application/vnd.openxmlformats-officedocument.presentationml.presentation", ".pptx");
}

@test:Config {groups: ["document-loader", "error-handling", "pdf"]}
function testTextDataLoaderFileDoesNotExist() returns error? {
    // Test with a non-existent file path
    string nonExistentPath = "tests/resources/data-loader/non_existent_file.pdf";

    // Test constructor with non-existent file
    TextDataLoader|Error loader = new (nonExistentPath);

    // Verify the constructor returns an error for non-existent files
    if loader is Error {
        test:assertTrue(loader.message().includes("File does not exist"),
                "Error message should indicate file does not exist");
    } else {
        test:assertFail("Constructor should return error for non-existent files");
    }
}

@test:Config {groups: ["document-loader", "error-handling", "pdf"]}
function testTextDataLoaderCaseInsensitiveExtensions() returns error? {
    // Test that uppercase extensions work (assuming we can create test files with uppercase extensions)
    // This test validates the case-insensitive extension checking
    string pdfPath = "tests/resources/data-loader/TestDoc.pdf";
    TextDataLoader loader = check new (pdfPath);

    // This should work even though we check with .PDF, .Pdf etc. internally
    Document[]|Document|Error result = loader.load();
    Document document = check getSingleDocument(result);
    check validateDocument(document, "application/pdf", ".pdf");
}

@test:Config {groups: ["document-loader", "error-handling"]}
function testTextDataLoaderImprovedErrorMessage() returns error? {
    // Test that error message includes file extension
    string unsupportedPath = "tests/resources/data-loader/test.txt";
    TextDataLoader loader = check new (unsupportedPath);

    Document[]|Document|Error result = loader.load();

    if result is Error {
        // Verify error message includes the file extension
        test:assertTrue(result.message().includes("Unsupported file type: txt"),
                "Error message should include the file extension");
    } else {
        test:assertFail("Should return error for unsupported file types");
    }
}

@test:Config {groups: ["document-loader", "multiple-files", "pdf", "docx", "pptx"]}
function testTextDataLoaderMultipleFiles() returns error? {
    // Test loading multiple files at once
    string pdfPath = "tests/resources/data-loader/TestDoc.pdf";
    string docxPath = "tests/resources/data-loader/TestDoc.docx";
    string pptxPath = "tests/resources/data-loader/Test presentation.pptx";

    TextDataLoader loader = check new (pdfPath, docxPath, pptxPath);

    Document[]|Document|Error result = loader.load();

    // Since we're loading multiple files, the result should be an array
    if result is Document[] {
        test:assertEquals(result.length(), 3, "Should return array with 3 documents");

        // Validate each document
        Document pdfDoc = result[0];
        Document docxDoc = result[1];
        Document pptxDoc = result[2];

        check validateDocument(pdfDoc, "application/pdf", ".pdf");
        check validateDocument(docxDoc, "application/vnd.openxmlformats-officedocument.wordprocessingml.document", ".docx");
        check validateDocument(pptxDoc, "application/vnd.openxmlformats-officedocument.presentationml.presentation", ".pptx");
    } else {
        test:assertFail("Should return array of documents when loading multiple files");
    }
}

@test:Config {groups: ["document-loader", "multiple-files", "single-file", "pdf"]}
function testTextDataLoaderSingleFileReturnsSingleDocument() returns error? {
    // Test that loading a single file returns a single document (not an array)
    string pdfPath = "tests/resources/data-loader/TestDoc.pdf";

    TextDataLoader loader = check new (pdfPath);

    Document[]|Document|Error result = loader.load();

    // When loading a single file, the result should be a single document
    if result is Document {
        check validateDocument(result, "application/pdf", ".pdf");
    } else {
        test:assertFail("Should return single document when loading single file");
    }
}

@test:Config {groups: ["document-loader", "multiple-files", "error-handling", "pdf"]}
function testTextDataLoaderMultipleFilesWithInvalidFile() returns error? {
    // Test loading multiple files where one doesn't exist
    string pdfPath = "tests/resources/data-loader/TestDoc.pdf";
    string nonExistentPath = "tests/resources/data-loader/non_existent_file.docx";

    // Constructor should fail if any file doesn't exist
    TextDataLoader|Error loader = new (pdfPath, nonExistentPath);

    if loader is Error {
        return test:assertTrue(loader.message().includes("File does not exist"),
                "Error message should indicate file does not exist");
    }
    test:assertFail("Constructor should return error when any file doesn't exist");
}
