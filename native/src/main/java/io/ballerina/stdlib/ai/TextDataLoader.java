/*
 *  Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
 *
 *  WSO2 LLC. licenses this file to you under the Apache License,
 *  Version 2.0 (the "License"); you may not use this file except
 *  in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing,
 *  software distributed under the License is distributed on an
 *  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 *  KIND, either express or implied.  See the License for the
 *  specific language governing permissions and limitations
 *  under the License.
 */

package io.ballerina.stdlib.ai;

import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.RecordType;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;
import org.apache.tika.exception.TikaException;
import org.apache.tika.metadata.Metadata;
import org.apache.tika.parser.ParseContext;
import org.apache.tika.parser.Parser;
import org.apache.tika.parser.microsoft.ooxml.OOXMLParser;
import org.apache.tika.parser.pdf.PDFParser;
import org.apache.tika.sax.BodyContentHandler;
import org.xml.sax.SAXException;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

import static io.ballerina.stdlib.ai.ModuleUtils.createError;

public class TextDataLoader {

    private static final String TYPE_FIELD = "type";
    private static final String METADATA_FIELD = "metadata";
    private static final String CONTENT_FIELD = "content";
    private static final String MIME_TYPE_FIELD = "mimeType";
    private static final String FILE_NAME_FIELD = "fileName";
    private static final String DEFAULT_MIME_TYPE = "application/octet-stream";
    private static final String TEXT_DOCUMENT_TYPE = "text";
    private static final String TEXT_DOCUMENT_RECORD = "TextDocument";
    private static final String X_TIKA_PREFIX = "x-tika";

    // MIME type constants
    private static final String MIME_TYPE_PDF = "application/pdf";
    private static final String MIME_TYPE_DOCX =
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    private static final String MIME_TYPE_PPTX =
            "application/vnd.openxmlformats-officedocument.presentationml.presentation";
    private static final String MIME_TYPE_DOC = "application/msword";
    private static final String MIME_TYPE_PPT = "application/vnd.ms-powerpoint";

    // File extension constants
    private static final String EXTENSION_PDF = "pdf";
    private static final String EXTENSION_DOCX = "docx";
    private static final String EXTENSION_PPTX = "pptx";
    private static final String EXTENSION_DOC = "doc";
    private static final String EXTENSION_PPT = "ppt";

    enum FileType {
        DOCX,
        PPTX;
    }

    record TextDocumentInfo(
            String mimeType,
            String fileName,
            Map<String, String> metadata,
            String content
    ) {

        static TextDocumentInfo fromPdf(String content, Map<String, String> metadata, String fileName) {
            return new TextDocumentInfo(MIME_TYPE_PDF, fileName, metadata, content);
        }

        static TextDocumentInfo fromDocx(String content, Map<String, String> metadata, String fileName) {
            return new TextDocumentInfo(MIME_TYPE_DOCX, fileName, metadata, content);
        }

        static TextDocumentInfo fromPptx(String content, Map<String, String> metadata, String fileName) {
            return new TextDocumentInfo(MIME_TYPE_PPTX, fileName, metadata, content);
        }

        BMap<BString, Object> toBallerinaTextDocument() {
            RecordType resultRecordType =
                    TypeCreator.createRecordType(TEXT_DOCUMENT_RECORD, ModuleUtils.getModule(), 0, false, 0);
            BMap<BString, Object> textDocument = ValueCreator.createRecordValue(resultRecordType);

            // Set the type field to "text"
            textDocument.put(StringUtils.fromString(TYPE_FIELD), StringUtils.fromString(TEXT_DOCUMENT_TYPE));
            
            // Set the content field
            textDocument.put(StringUtils.fromString(CONTENT_FIELD), StringUtils.fromString(content()));

            // Create metadata map with mimeType, fileName and other metadata
            BMap<BString, Object> metadataMap = ValueCreator.createMapValue();
            metadataMap.put(StringUtils.fromString(MIME_TYPE_FIELD),
                    StringUtils.fromString(mimeType() != null ? mimeType() : DEFAULT_MIME_TYPE));
            metadataMap.put(StringUtils.fromString(FILE_NAME_FIELD), StringUtils.fromString(fileName()));
            
            // Add all other metadata
            for (Map.Entry<String, String> entry : metadata().entrySet()) {
                metadataMap.put(StringUtils.fromString(entry.getKey()), StringUtils.fromString(entry.getValue()));
            }
            
            textDocument.put(StringUtils.fromString(METADATA_FIELD), metadataMap);

            return textDocument;
        }
    }

    public static Object readPdf(BString filePath) {
        String path = filePath.getValue();
        TextDocumentInfo docInfo;
        try {
            docInfo = parsePDF(path);
            return docInfo.toBallerinaTextDocument();
        } catch (IOException | TikaException | SAXException e) {
            return createError("Error reading document: " + e.getMessage());
        } catch (RuntimeException e) {
            return createError("Unexpected error: " + e.getMessage());
        }
    }

    public static Object readDocx(BString filePath) {
        String path = filePath.getValue();
        TextDocumentInfo docInfo;
        try {
            docInfo = parseOfficeX(path, FileType.DOCX);
            return docInfo.toBallerinaTextDocument();
        } catch (IOException | TikaException | SAXException e) {
            return createError("Error reading document: " + e.getMessage());
        } catch (RuntimeException e) {
            return createError("Unexpected error: " + e.getMessage());
        }
    }

    public static Object readPptx(BString filePath) {
        String path = filePath.getValue();
        TextDocumentInfo docInfo;
        try {
            docInfo = parseOfficeX(path, FileType.PPTX);
            return docInfo.toBallerinaTextDocument();
        } catch (IOException | TikaException | SAXException e) {
            return createError("Error reading document: " + e.getMessage());
        } catch (RuntimeException e) {
            return createError("Unexpected error: " + e.getMessage());
        }
    }

    static TextDocumentInfo parsePDF(String path) throws IOException, TikaException, SAXException {
        try (InputStream inputStream = new FileInputStream(path)) {
            Parser parser = new PDFParser();
            BodyContentHandler handler = new BodyContentHandler(-1);
            Metadata metadata = new Metadata();
            ParseContext context = new ParseContext();
            parser.parse(inputStream, handler, metadata, context);
            String content = handler.toString();
            return TextDocumentInfo.fromPdf(content, extractMetadata(metadata), path);
        }
    }

    static TextDocumentInfo parseOfficeX(String path, FileType fileType)
            throws IOException, TikaException, SAXException {
        try (InputStream inputStream = new FileInputStream(path)) {
            Parser parser = new OOXMLParser();
            BodyContentHandler handler = new BodyContentHandler(-1);
            Metadata metadata = new Metadata();
            ParseContext context = new ParseContext();
            parser.parse(inputStream, handler, metadata, context);
            String content = handler.toString();

            return switch (fileType) {
                case DOCX -> TextDocumentInfo.fromDocx(content, extractMetadata(metadata), path);
                case PPTX -> TextDocumentInfo.fromPptx(content, extractMetadata(metadata), path);
            };
        }
    }

    static String parseOfficeX(String path) {
        try (InputStream inputStream = new FileInputStream(path)) {
            Parser parser = new OOXMLParser();
            BodyContentHandler handler = new BodyContentHandler(-1);
            Metadata metadata = new Metadata();
            ParseContext context = new ParseContext();
            parser.parse(inputStream, handler, metadata, context);
            return handler.toString();
        } catch (IOException | TikaException | SAXException e) {
            throw new RuntimeException(e);
        }
    }

    static Map<String, String> extractMetadata(Metadata metadata) {
        Map<String, String> metadataMap = new HashMap<>();
        for (String name : metadata.names()) {
            if (name != null && name.toLowerCase(Locale.ENGLISH).startsWith(X_TIKA_PREFIX)) {
                continue;
            }
            String[] values = metadata.getValues(name);
            if (values != null && values.length > 0) {
                String value = values.length == 1 ? values[0] : String.join("; ", values);
                metadataMap.put(name, value);
            }
        }
        return metadataMap;
    }

}
