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

import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

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

import static io.ballerina.stdlib.ai.ModuleUtils.createError;

public class DocReader {

    private static final String MIME_TYPE_FIELD = "mimeType";
    private static final String EXTENSION_FIELD = "extension";
    private static final String METADATA_FIELD = "metadata";
    private static final String CONTENT_FIELD = "content";
    private static final String DEFAULT_MIME_TYPE = "application/octet-stream";
    private static final String DOCUMENT_INFO_RECORD = "DocumentInfo";
    private static final String X_TIKA_PREFIX = "x-tika";

    record DocumentInfo(
            String mimeType,
            String extension,
            Map<String, String> metadata,
            String content
    ) {

        static DocumentInfo fromPdf(String content, Map<String, String> metadata) {
            return new DocumentInfo("application/pdf", "pdf", metadata, content);
        }

        static DocumentInfo fromDocx(String content, Map<String, String> metadata) {
            return new DocumentInfo("application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                    "docx", metadata, content);
        }

        static DocumentInfo fromPptx(String content, Map<String, String> metadata) {
            return new DocumentInfo("application/vnd.openxmlformats-officedocument.presentationml.presentation",
                    "pptx", metadata, content);
        }

        static DocumentInfo fromDoc(String content, Map<String, String> metadata) {
            return new DocumentInfo("application/msword", "doc", metadata, content);
        }

        static DocumentInfo fromPpt(String content, Map<String, String> metadata) {
            return new DocumentInfo("application/vnd.ms-powerpoint", "doc", metadata, content);
        }

        BMap<BString, Object> toBallerinaRecord() {
            RecordType resultRecordType =
                    TypeCreator.createRecordType(DOCUMENT_INFO_RECORD, ModuleUtils.getModule(), 0, false, 0);
            BMap<BString, Object> documentInfo = ValueCreator.createRecordValue(resultRecordType);

            documentInfo.put(StringUtils.fromString(MIME_TYPE_FIELD),
                    StringUtils.fromString(mimeType() != null ? mimeType() : DEFAULT_MIME_TYPE));
            documentInfo.put(StringUtils.fromString(EXTENSION_FIELD), StringUtils.fromString(extension()));

            BMap<BString, Object> metadataMap = toBallerinaMap(metadata());
            documentInfo.put(StringUtils.fromString(METADATA_FIELD), metadataMap);
            documentInfo.put(StringUtils.fromString(CONTENT_FIELD), StringUtils.fromString(content()));

            return documentInfo;
        }
    }

    public static Object readPdf(BString filePath) {
        String path = filePath.getValue();
        DocumentInfo docInfo;
        try {
            docInfo = parsePDF(path);
            return docInfo.toBallerinaRecord();
        } catch (IOException | TikaException | SAXException e) {
            return createError("Error reading document: " + e.getMessage());
        } catch (RuntimeException e) {
            return createError("Unexpected error: " + e.getMessage());
        }
    }

    static DocumentInfo parsePDF(String path) throws IOException, TikaException, SAXException {
        try (InputStream inputStream = new FileInputStream(path)) {
            Parser parser = new PDFParser();
            BodyContentHandler handler = new BodyContentHandler(-1);
            Metadata metadata = new Metadata();
            ParseContext context = new ParseContext();
            parser.parse(inputStream, handler, metadata, context);
            String content = handler.toString();
            return DocumentInfo.fromPdf(content, extractMetadata(metadata));
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

    static BMap<BString, Object> toBallerinaMap(Map<String, String> map) {
        BMap<BString, Object> metadataMap = ValueCreator.createMapValue();
        for (String name : map.keySet()) {
            metadataMap.put(StringUtils.fromString(name), StringUtils.fromString(map.get(name)));
        }
        return metadataMap;
    }
}
