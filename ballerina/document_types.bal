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

# Enumeration of MIME types for different document formats
public enum DocumentMimeType {
    # Plain text format
    TEXT_PLAIN = "text/plain",
    # HTML format
    TEXT_HTML = "text/html",
    # CSS format
    TEXT_CSS = "text/css",
    # CSV format
    TEXT_CSV = "text/csv",
    # JPEG image format
    IMAGE_JPEG = "image/jpeg",
    # PNG image format
    IMAGE_PNG = "image/png",
    # GIF image format
    IMAGE_GIF = "image/gif",
    # SVG image format
    IMAGE_SVG = "image/svg+xml",
    # WebP image format
    IMAGE_WEBP = "image/webp",
    # JSON format
    APPLICATION_JSON = "application/json",
    # XML format
    APPLICATION_XML = "application/xml",
    # PDF format
    APPLICATION_PDF = "application/pdf",
    # ZIP archive format
    APPLICATION_ZIP = "application/zip",
    # Binary data format
    APPLICATION_OCTET_STREAM = "application/octet-stream"
}

# Enumeration of supported audio formats
public enum AudioFormat {
    # WAV audio format
    WAV = "wav",
    # MP3 audio format
    MP3 = "mp3"
}

# Represents a URL pointing to the content of a document
public type Url record {|
    # The URL pointing to the content of the document
    string url;
|};

# Record type for file ID reference of a document
public type FileId record {|
    # Unique identifier for the file
    string fileId;
|};

# Represents additional metadata associated with documents
public type DocumentMetaData record {|
    json...;
|};

# Represents the common structure for all document types
public type Document record {|
    # The type of document (text, image, audio, or file)
    DocumentKind 'type;
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
    # Optional MIME type specification for the file
    DocumentMimeType mimeType?;
|};
