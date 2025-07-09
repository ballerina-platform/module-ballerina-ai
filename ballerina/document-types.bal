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

import ballerina/time;

# Represents additional metadata associated with documents or nodes.
public type Metadata record {|
    # MIME type specification for the file
    string mimeType?;
    # File name for the document
    string fileName?;
    # File size in bytes
    decimal fileSize?;
    # Creation timestamp of the file
    time:Utc createdAt?;
    # Modification timestamp of the file
    time:Utc modifiedAt?;
    json...;
|};

# Represents the common structure for all document types
public type Document record {|
    # The type of the document or chunk
    string 'type;
    # Associated metadata
    Metadata metadata?;
    # The actual content
    anydata content;
|};

# Represents documents containing plain text content
public type TextDocument record {|
    *Document;
    # Fixed type for the text document
    readonly "text" 'type = "text";
    # The text content of the document
    string content;
|};

# Represents a chunk of a document.
public type Chunk record {|
    *Document;
|};

# Represents a chunk of text within a document.
public type TextChunk record {|
    *Chunk;
    # Fixed type for the text chunk
    readonly "text-chunk" 'type = "text-chunk";
    # The text content of the chunk
    string content;
|};
