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

public isolated class TextDataLoader {
    *DataLoader;
    final string path;

    public isolated function init(string path) returns Error? {
        // Check if the file exists by trying to get metadata
        file:MetaData|error metadata = file:getMetaData(path);
        if metadata is error {
            return error Error("File does not exist: " + path);
        }
        self.path = path;
    }

    public isolated function load() returns Document[]|Document|Error {

        if self.path.endsWith(".pdf") {
            TextDocument|error result = readPdfFromJava(self.path);
            if result is error {
                return error Error(result.message());
            }
            return result;
        } else if self.path.endsWith(".docx") {
            TextDocument|error result = readDocxFromJava(self.path);
            if result is error {
                return error Error(result.message());
            }
            return result;
        } else if self.path.endsWith(".pptx") {
            TextDocument|error result = readPptxFromJava(self.path);
            if result is error {
                return error Error(result.message());
            }
            return result;
        }
        return error("Unsupported file type");
    }
}

isolated function readPdfFromJava(string path) returns TextDocument|error = @java:Method {
    'class: "io.ballerina.stdlib.ai.TextDataLoader",
    name: "readPdf"
} external;

isolated function readDocxFromJava(string path) returns TextDocument|error = @java:Method {
    'class: "io.ballerina.stdlib.ai.TextDataLoader",
    name: "readDocx"
} external;

isolated function readPptxFromJava(string path) returns TextDocument|error = @java:Method {
    'class: "io.ballerina.stdlib.ai.TextDataLoader",
    name: "readPptx"
} external;
