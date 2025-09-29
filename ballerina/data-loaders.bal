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

import ballerina/file;
import ballerina/io;
import ballerina/jballerina.java;

# Represents a data loader that can load documents from various sources.
public type DataLoader isolated object {
    # Loads documents from a source.
    # + return - document or an array of documents, or an `ai:Error` if the loading fails
    public isolated function load() returns Document[]|Document|Error;
};

# Dataloader that can be used to load supported file types as `TextDocument`s.
# Currently only supports `pdf`, `docx`, `markdown`, `html`, and `pptx` file types.
public isolated class TextDataLoader {
    *DataLoader;
    final readonly & string[] paths;

    # Initializes the data loader with the given paths.
    # + paths - The paths to the files to load
    # + return - an error if the file does not exist
    public isolated function init(string... paths) returns Error? {
        // Check if the file exists by trying to get metadata
        foreach string path in paths {
            file:MetaData|error metadata = file:getMetaData(path);
            if metadata is error {
                return error Error("File does not exist: " + path);
            }
        }
        self.paths = paths.cloneReadOnly();
    }

    # Loads documents as `TextDocument`s from a source.
    # + return - document or an array of documents, or an `ai:Error` if the loading fails
    public isolated function load() returns Document[]|Document|Error {
        Document[] documents = from string path in self.paths
            select check loadDocument(path);
        if documents.length() == 1 {
            return documents[0];
        }
        return documents;
    }
}

isolated function loadDocument(string path) returns Document|Error {
    string? fileType = getFileType(path);
    if fileType is () {
        string extension = getFileExtension(path);
        return error Error(string `Unsupported file type: ${extension}`);
    }

    match fileType {
        HTML|HTM|MARKDOWN => {
            return readMarkupDocument(path);
        }
        PDF => {
            return readPdfNative(path);
        }
        DOCX => {
            return readDocxNative(path);
        }
        PPTX => {
            return readPptxNative(path);
        }
    }
    return error Error("Unexpected error in file type processing");
}

enum SupportedFileType {
    PDF = "pdf",
    DOCX = "docx",
    PPTX = "pptx",
    HTML = "html",
    HTM = "htm",
    MARKDOWN = "md"
}

isolated function getFileType(string path) returns SupportedFileType? {
    match getFileExtension(path) {
        "html" => {return HTML;}
        "htm" => {return HTM;}
        "md" => {return MARKDOWN;}
        "pdf" => {return PDF;}
        "docx" => {return DOCX;}
        "pptx" => {return PPTX;}
        _ => {return ();}
    }
}

isolated function getFileExtension(string path) returns string {
    int? lastDotIndex = path.toLowerAscii().lastIndexOf(".");
    if lastDotIndex is () {
        return "unknown";
    }
    return path.substring(lastDotIndex + 1);
}

isolated function readMarkupDocument(string filePath) returns TextDocument|Error {
    do {
        string fileName = check file:basename(filePath);
        file:MetaData meta = check file:getMetaData(filePath);
        string content = check io:fileReadString(filePath);
        Metadata metadata = {fileName, modifiedAt: meta.modifiedTime, fileSize: <decimal>meta.size};
        return {content, metadata};
    } on fail error e {
        return error(string `failed to create document from file '${filePath}': ${e.message()}`, e);
    }
}

isolated function readPdfNative(string path) returns TextDocument|Error = @java:Method {
    'class: "io.ballerina.stdlib.ai.TextDataLoader",
    name: "readPdf"
} external;

isolated function readDocxNative(string path) returns TextDocument|Error = @java:Method {
    'class: "io.ballerina.stdlib.ai.TextDataLoader",
    name: "readDocx"
} external;

isolated function readPptxNative(string path) returns TextDocument|Error = @java:Method {
    'class: "io.ballerina.stdlib.ai.TextDataLoader",
    name: "readPptx"
} external;
