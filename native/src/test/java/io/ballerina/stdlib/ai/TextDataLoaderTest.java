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

import org.apache.tika.exception.TikaException;
import org.testng.Assert;
import org.testng.annotations.Test;
import org.xml.sax.SAXException;

import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;

public class TextDataLoaderTest {

    @Test
    public void testParsePDF() throws TikaException, IOException, SAXException {
        Path resourcePath = Paths.get(System.getProperty("user.dir"))
                .resolve("src/test/resources")
                .resolve("doc-reader-test/TestDoc.pdf");
        var doc = TextDataLoader.parsePDF(resourcePath.toString());
        String content = doc.content();

        Assert.assertNotNull(content, "PDF parsing result should not be null");
        Assert.assertFalse(content.trim().isEmpty(), "PDF parsing result should not be empty");
        Assert.assertTrue(content.length() > 100, "PDF should contain substantial content");
    }

    @Test
    public void testParseOfficeXDocx() {
        Path resourcePath = Paths.get(System.getProperty("user.dir"))
                .resolve("src/test/resources")
                .resolve("doc-reader-test/TestDoc.docx");

        String result = TextDataLoader.parseOfficeX(resourcePath.toString());

        Assert.assertNotNull(result, "DOCX parsing result should not be null");
        Assert.assertFalse(result.trim().isEmpty(), "DOCX parsing result should not be empty");
        Assert.assertTrue(result.length() > 10, "DOCX should contain substantial content");
    }

    @Test
    public void testParseOfficeXPptx() {
        Path resourcePath = Paths.get(System.getProperty("user.dir"))
                .resolve("src/test/resources")
                .resolve("doc-reader-test/Test presentation.pptx");

        String result = TextDataLoader.parseOfficeX(resourcePath.toString());

        Assert.assertNotNull(result, "PPTX parsing result should not be null");
        Assert.assertFalse(result.trim().isEmpty(), "PPTX parsing result should not be empty");
        Assert.assertTrue(result.length() > 10, "PPTX should contain substantial content");
    }

    @Test(expectedExceptions = RuntimeException.class)
    public void testParseOfficeXWithInvalidPath() {
        TextDataLoader.parseOfficeX("non-existent-file.docx");
    }
}
