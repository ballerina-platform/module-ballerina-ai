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

# Splits content into documents based on line breaks.
# Each non-empty line becomes a separate document with the line content.
# Empty lines and lines containing only whitespace are filtered out.
#
# + content - The input text content to be split by lines
# + return - Array of documents, one per non-empty line
public isolated function splitDocumentByLine(string content) returns Document[] {
    string[] lines = re `\n`.split(content);
    return from string line in lines
        where line.trim() != ""
        select {content: line.trim()};
}
