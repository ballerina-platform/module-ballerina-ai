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

import ballerina/jballerina.java;
import ballerina/file;

# Represents a data loader that can load documents from various sources.
public type DataLoader isolated object {
    # Loads documents from a source.
    # + return - document or an array of documents, or an `ai:Error` if the loading fails
    public isolated function load() returns Document[]|Document|Error;
};

# Dataloader that can be used to load supported file types as `TextDocument`s.
# Currently only supports `pdf`, `docx` and `pptx` file types.
public isolated class TextDataLoader {
    *DataLoader;
    final readonly & string[] paths;

    public isolated function init(string ...paths) returns Error? {
        // Check if the file exists by trying to get metadata
        foreach string path in paths {
            file:MetaData|error metadata = file:getMetaData(path);
            if metadata is error {
                return error Error("File does not exist: " + path);
            }
        }
        self.paths = paths.cloneReadOnly();
    }

    public isolated function load() returns Document[]|Document|Error {
        Document[] documents = from string path in self.paths select check loadDocument(path);
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
            "pdf" => {
                TextDocument|error result = readPdfNative(path);
                if result is error {
                    return error Error(result.message());
                }
                return result;
            }
            "docx" => {
                TextDocument|error result = readDocxNative(path);
                if result is error {
                    return error Error(result.message());
                }
                return result;
            }
            "pptx" => {
                TextDocument|error result = readPptxNative(path);
                if result is error {
                    return error Error(result.message());
                }
                return result;
            }
        }
        return error Error("Unexpected error in file type processing");
}

isolated function getFileType(string path) returns "pdf"|"docx"|"pptx"? {
    string lowerPath = path.toLowerAscii();
    if lowerPath.endsWith(".pdf") { return "pdf"; }
    if lowerPath.endsWith(".docx") { return "docx"; }
    if lowerPath.endsWith(".pptx") { return "pptx"; }
    return ();
}

isolated function getFileExtension(string path) returns string {
    int? lastDotIndex = path.lastIndexOf(".");
    if lastDotIndex is () {
        return "unknown";
    }
    return path.substring(lastDotIndex + 1);
}

isolated function readPdfNative(string path) returns TextDocument|error = @java:Method {
    'class: "io.ballerina.stdlib.ai.TextDataLoader",
    name: "readPdf"
} external;

isolated function readDocxNative(string path) returns TextDocument|error = @java:Method {
    'class: "io.ballerina.stdlib.ai.TextDataLoader",
    name: "readDocx"
} external;

isolated function readPptxNative(string path) returns TextDocument|error = @java:Method {
    'class: "io.ballerina.stdlib.ai.TextDataLoader",
    name: "readPptx"
} external;
