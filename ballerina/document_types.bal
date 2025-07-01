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

import ballerina/constraint;
import ballerina/time;

final string:RegExp urlRegExpr = re `[a-zA-Z][a-zA-Z0-9+.-]*://(?:[^@\s"']+@)?[^\s"']+`;

# Enumeration of supported document types.
public enum DocumentKind {
    # Text document type
    TEXT = "text",
    # Image document type  
    IMAGE = "image",
    # Audio document type
    AUDIO = "audio",
    # File document type
    FILE = "file"
}

# Represents a URL.
@constraint:String {
    pattern: {
        value: urlRegExpr,
        message: "Must be a valid URL"
    }
}
public type Url string;

# Represents an ID referring to a file.
public type FileId record {|
    # Unique identifier for the file
    string fileId;
|};

# Represents metadata associated with documents.
public type DocumentMetadata record {|
    # MIME type of the document
    string mimeType?;
    # Name of the document
    string documentName?;
    # Document size in bytes
    int documentSize?;
    # Creation timestamp of the document
    time:Utc createdAt?;
    # Modification timestamp of the document
    time:Utc modifiedAt?;
    json...;
|};

# Represents the common structure for all document types.
public type Document record {|
    # The type of document (text, image, audio, file, etc.)
    string 'type;
    # Metadata associated with the document
    DocumentMetadata metadata?;
    # The content of the document
    anydata content;
|};

# Represents documents containing plain text content.
public type TextDocument record {|
    *Document;
    # Fixed type for the text document
    readonly TEXT 'type = TEXT;
    # The text content of the document
    string content;
|};
