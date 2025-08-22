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

import org.testng.Assert;
import org.testng.annotations.Test;

import java.nio.file.Path;
import java.nio.file.Paths;

public class DocReaderTest {

    @Test
    public void testParsePDF() {
        Path resourcePath = Paths.get(System.getProperty("user.dir"))
                .resolve("src/test/resources")
                .resolve("doc-reader-test/Operating_Systems_From_0_to_1.pdf");
        
        String result = DocReader.parsePDF(resourcePath.toString());
        
        Assert.assertNotNull(result, "PDF parsing result should not be null");
        Assert.assertFalse(result.trim().isEmpty(), "PDF parsing result should not be empty");
        Assert.assertTrue(result.length() > 100, "PDF should contain substantial content");
    }

    @Test(expectedExceptions = RuntimeException.class)
    public void testParsePDFWithInvalidPath() {
        DocReader.parsePDF("non-existent-file.pdf");
    }
}