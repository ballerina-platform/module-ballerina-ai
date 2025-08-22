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

# Represents a data loader that can load documents from various sources.
public type DataLoader isolated object {
    # Loads documents from a source.
    # + return - document or an array of documents, or an `ai:Error` if the loading fails
    public isolated function load() returns Document[]|Document|Error;
};

// FIXME: check the name in issue
public isolated class TextDataLoader {
    *DataLoader;
    final string path;

    public isolated function init(string path) {
        self.path = path;
    }

    public isolated function load() returns Document[]|Document|Error {
        if self.path.endsWith(".pdf") {
            return loadPdf(self.path);
        } else if self.path.endsWith(".docx") {
            return loadDocx(self.path);
        } else if self.path.endsWith(".pptx") {
            return loadPptx(self.path);
        }
        return error("Unsupported file type");
    }
}

isolated function loadPdf(string path) returns TextDocument|Error {
    // FIXME:
    DocumentInfo|error docInfo = readPdfFromJava(path);
    if docInfo is error {
        return error Error(docInfo.message());
    }

    Metadata metadata = {...docInfo.metadata};

    metadata.fileName = path;
    metadata.mimeType = docInfo.mimeType;

    return {
        content: docInfo.content,
        metadata
    };
}

isolated function loadDocx(string path) returns TextDocument|Error {
    DocumentInfo|error docInfo = readDocxFromJava(path);
    if docInfo is error {
        return error Error(docInfo.message());
    }

    Metadata metadata = {...docInfo.metadata};

    metadata.fileName = path;
    metadata.mimeType = docInfo.mimeType;

    return {
        content: docInfo.content,
        metadata
    };
}

isolated function loadPptx(string path) returns TextDocument|Error {
    DocumentInfo|error docInfo = readPptxFromJava(path);
    if docInfo is error {
        return error Error(docInfo.message());
    }

    Metadata metadata = {...docInfo.metadata};

    metadata.fileName = path;
    metadata.mimeType = docInfo.mimeType;

    return {
        content: docInfo.content,
        metadata
    };
}

isolated function readPdfFromJava(string path) returns DocumentInfo|error = @java:Method {
    'class: "io.ballerina.stdlib.ai.DocReader",
    name: "readPdf"
} external;

isolated function readDocxFromJava(string path) returns DocumentInfo|error = @java:Method {
    'class: "io.ballerina.stdlib.ai.DocReader",
    name: "readDocx"
} external;

isolated function readPptxFromJava(string path) returns DocumentInfo|error = @java:Method {
    'class: "io.ballerina.stdlib.ai.DocReader",
    name: "readPptx"
} external;

type DocumentInfo record {
    string mimeType;
    string extension;
    map<string> metadata;
    string content;
};
