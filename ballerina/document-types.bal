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
    # Index of the chunk in the document
    int index?;
    # Unique identifier for the chunk
    int id?;
    # Previous chunk id if a semantically meaningful chunk was broken into multiple chunks
    int prev?;
    # Header of the chunk if the chunk belonged to a single header
    string header?;
    # Language of the chunk if the chunk is a code block
    string language?;
    # Header of the chunk if the chunk belongs to a single h1 header
    string header1?;
    # Header of the chunk if the chunk belongs to a single h2 header
    string header2?;
    # Header of the chunk if the chunk belongs to a single h3 header
    string header3?;
    # Header of the chunk if the chunk belongs to a single h4 header
    string header4?;
    # Header of the chunk if the chunk belongs to a single h5 header
    string header5?;
    # Header of the chunk if the chunk belongs to a single h6 header
    string header6?;
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

# Represents a URL.
@constraint:String {
    pattern: {
        value: urlRegExpr,
        message: "Must be a valid URL"
    }
}
public type Url string;

# Represents an image document.
public type ImageDocument record {|
    *Document;
    # Fixed type identifier for image documents
    readonly "image" 'type = "image";
    # Image content, either a URL or binary data
    Url|byte[] content;
|};

# Represents an audio document.
public type AudioDocument record {|
    *Document;
    # Fixed type identifier for audio documents
    readonly "audio" 'type = "audio";
    # Audio content, either a URL or binary data
    Url|byte[] content;
|};

# Represents an ID referring to a file.
public type FileId record {|
    # Unique identifier for the file
    string fileId;
|};

# Represents a generic file document.
public type FileDocument record {|
    *Document;
    # Fixed type identifier for file documents
    readonly "file" 'type = "file";
    # File content, a URL, binary data, or a file ID reference
    byte[]|Url|FileId content;
|};

# Represents a binary document.
public type BinaryDocument record {|
    *Document;
    # Fixed type identifier for binary documents
    readonly "binary" 'type = "binary";
    # Document content as binary data
    byte[] content;
|};
