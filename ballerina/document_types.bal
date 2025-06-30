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

final string:RegExp HTTP_URL = re `(http|https)://[^\s"']+`;
final string:RegExp FTP_URL = re `ftp://[^\s"']+`;
final string:RegExp FTPS_URL = re `ftps://[^\s"']+`;
final string:RegExp FTP_WITH_AUTH_URL = re `ftp://[^@\s"']+@[^\s"']+`;

final string:RegExp GOOGLE_DRIVE_FILE_URL = re `https://drive\.google\.com/file/d/[a-zA-Z0-9_-]+`;
final string:RegExp GOOGLE_DRIVE_DOWNLOAD_URL = re `https://drive\.google\.com/uc\?export=download&id=[a-zA-Z0-9_-]+`;
final string:RegExp GOOGLE_DRIVE_FOLDER_URL = re `https://drive\.google\.com/drive/folders/[a-zA-Z0-9_-]+`;

final string:RegExp AMAZON_S3_URL = re `https://[a-zA-Z0-9-]+\.s3\.amazonaws\.com/[^\s"']+`;
final string:RegExp AMAZON_S3_CUSTOM_DOMAIN_URL = re `https://[a-zA-Z0-9.-]+/[^\s"']+`;
final string:RegExp AMAZON_S3_PRESIGNED_URL = re `https://[a-zA-Z0-9-]+\.s3\.amazonaws\.com/[^\s"']+\?[^\s"']+`;

final string:RegExp ONEDRIVE_FILE_URL = re `https://onedrive\.live\.com/embed\?resid=[a-zA-Z0-9!_-]+`;
final string:RegExp ONEDRIVE_DOWNLOAD_URL = re `https://onedrive\.live\.com/download\?resid=[a-zA-Z0-9!_-]+`;

final string:RegExp GITHUB_RAW_URL = re `https://raw\.githubusercontent\.com/[^\s"']+`;
final string:RegExp GITHUB_REPO_FILE_URL = re `https://github\.com/[^\s"']+/blob/[^\s"']+`;

final string:RegExp DROPBOX_URL = re `https://www\.dropbox\.com/s/[a-zA-Z0-9]+/[^\s"']+`;
final string:RegExp DROPBOX_DOWNLOAD_URL = re `https://www\.dropbox\.com/s/[a-zA-Z0-9]+/[^\s"']+\?dl=[01]`;

final string:RegExp LOCAL_FILE_WINDOWS_URL = re `file:///[a-zA-Z]:\\[^\s"']+`;
final string:RegExp LOCAL_FILE_UNIX_URL = re `file:////[^\s"']+`;

final string:RegExp FILE_URL = re `HTTP_URL|FTP_URL|FTPS_URL|FTP_WITH_AUTH_URL|GOOGLE_DRIVE_FILE_URL|GOOGLE_DRIVE_DOWNLOAD_URL|GOOGLE_DRIVE_FOLDER_URL|AMAZON_S3_URL|AMAZON_S3_CUSTOM_DOMAIN_URL|AMAZON_S3_PRESIGNED_URL|ONEDRIVE_FILE_URL|ONEDRIVE_DOWNLOAD_URL|GITHUB_RAW_URL|GITHUB_REPO_FILE_URL|DROPBOX_URL|DROPBOX_DOWNLOAD_URL|LOCAL_FILE_WINDOWS_URL|LOCAL_FILE_UNIX_URL`;

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

# Represents a URL pointing to the content of a document
@constraint:String {
    pattern: {
        value: FILE_URL,
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
    # The type of document (text, image, audio, or file)
    string 'type;
    # Metadata associated with the document
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
    string format = "wav";
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
