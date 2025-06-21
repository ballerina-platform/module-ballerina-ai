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

# Represents a vector store that provides persistence, management, and search capabilities for vector embeddings.
public type VectorStore isolated object {

    # Adds vector entries to the store.
    #
    # + entries - The array of vector entries to add
    # + return - An `Error` if the operation fails; otherwise, `nil`
    public isolated function add(VectorEntry[] entries) returns Error?;

    # Searches for vectors in the store that are most similar to a given query.
    #
    # + query - The vector store query that specifies the search criteria
    # + return - An array of matching vectors with their similarity scores,
    # or an `Error` if the operation fails
    public isolated function query(VectorStoreQuery query) returns VectorMatch[]|Error;

    # Deletes a vector entry from the store by its unique ID.
    #
    # + id - The unique identifier of the vector entry to delete
    # + return - An `Error` if the operation fails; otherwise, `nil`
    public isolated function delete(string id) returns Error?;
};
