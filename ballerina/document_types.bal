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

string:RegExp ftpUrlRegex = re `ftp://[^\s"'<>]+`;
string:RegExp httpUrlRegex = re `http://[^\s"'<>]+`;
string:RegExp googleDriveUrlRegex = re `https://drive.google.com/[^\s"'<>]+`;

# Enumeration of supported document types
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

# Enumeration of supported audio formats
public enum AudioFormat {
    # WAV audio format
    WAV = "wav",
    # MP3 audio format
    MP3 = "mp3"
}

# Represents a URL pointing to the content of a document
@constraint:String {
    pattern: {
        value: re `${httpUrlRegex}|${ftpUrlRegex}|${googleDriveUrlRegex}`,
        message: "A valid URL pointing to the document content, must be either http, ftp or google drive URL."
    }
}
public type Url string;

# Record type for file ID reference of a document
public type FileId record {|
    # Unique identifier for the file
    string fileId;
|};

# Represents additional metadata associated with documents
public type DocumentMetaData record {|
    # Optional MIME type specification for the file
    string mimeType?;
    # Optional file name for the document
    string fileName?;
    # Optional file size in bytes
    decimal fileSize?;
    # Optional creation timestamp of the file
    time:Utc createdAt?;
    # Optional modification timestamp of the file
    time:Utc modifiedAt?;
    json...;
|};

# Represents the common structure for all document types
public type Document record {|
    # The type of document (text, image, audio, or file)
    string 'type;
    # Optional metadata associated with the document
    DocumentMetaData metadata?;
    # The actual content of the document
    anydata content;
|};

# Represents documents containing plain text content
public type TextDocument record {|
    *Document;
    # Fixed type for the text document
    readonly TEXT 'type = TEXT;
    # The text content of the document
    string content;
|};

# Represents documents containing image data
public type ImageDocument record {|
    *Document;
    # Fixed type identifier for image documents
    readonly IMAGE 'type = IMAGE;
    # Image content - can be either a URL reference or binary data
    Url|byte[] content;
|};

# Represents documents containing audio data
public type AudioDocument record{|
    *Document;
    # Fixed type identifier for audio documents
    readonly AUDIO 'type = AUDIO;
    # Audio format specification (defaults to WAV)
    AudioFormat format = WAV;
    # Audio content - can be either a URL reference or binary data
    Url|byte[] content;
|};

# Represents generic file documents with various content sources
public type FileDocument record {|
    *Document;
    # Fixed type identifier for file documents
    readonly FILE 'type = FILE;
    # File content - can be URL, binary data, or file ID reference
    byte[]|Url|FileId content;
|};
