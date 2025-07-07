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

import ballerina/math.vector;

# Represents a vector store that provides persistence, management, and search capabilities for vector embeddings.
public type VectorStore distinct isolated object {

    # Adds vector entries to the store.
    #
    # + entries - The array of vector entries to add
    # + return - An `ai:Error` if the operation fails; otherwise, `nil`
    public isolated function add(VectorEntry[] entries) returns Error?;

    # Searches for vectors in the store that are most similar to a given query.
    #
    # + query - The vector store query that specifies the search criteria
    # + return - An array of matching vectors with their similarity scores,
    # or an `ai:Error` if the operation fails
    public isolated function query(VectorStoreQuery query) returns VectorMatch[]|Error;

    # Deletes a vector entry from the store by its unique ID.
    #
    # + id - The unique identifier of the vector entry to delete
    # + return - An `ai:Error` if the operation fails; otherwise, `nil`
    public isolated function delete(string id) returns Error?;
};

# An in-memory vector store implementation that provides simple storage for vector entries.
public distinct isolated class InMemoryVectorStore {
    *VectorStore;
    private final VectorEntry[] entries = [];
    private final int topK;
    private final SimilarityMetric similarityMetric;

    # Initializes a new in-memory vector store.
    #
    # + topK - The maximum number of top similar vectors to return in query results
    # + similarityMetric - The metric used for vector similarity
    public isolated function init(int topK = 3, SimilarityMetric similarityMetric = COSINE) {
        self.topK = topK;
        self.similarityMetric = similarityMetric;
    }

    # Adds vector entries to the in-memory store.
    # Only supports dense vectors in this implementation.
    #
    # + entries - Array of vector entries to store
    # + return - `nil` on success; an Error if non-dense vectors are provided
    public isolated function add(VectorEntry[] entries) returns Error? {
        foreach VectorEntry entry in entries {
            if entry.embedding !is Vector {
                return error Error("InMemoryVectorStore supports dense vectors exclusively");
            }
        }
        readonly & VectorEntry[] clonedEntries = entries.cloneReadOnly();
        lock {
            self.entries.push(...clonedEntries);
        }
    }

    # Queries the vector store for vectors similar to the given query.
    #
    # + query - The query containing the embedding vector and optional filters
    # + return - An array of vector matches sorted by similarity score (limited to topK), 
    # or an `ai:Error` if the query fails
    public isolated function query(VectorStoreQuery query) returns VectorMatch[]|Error {
        if query.embedding !is Vector {
            return error Error("InMemoryVectorStore supports dense vectors exclusively");
        }

        lock {
            VectorMatch[] sorted = from var entry in self.entries
                let float similarity = self.calculateSimilarity(<Vector>query.embedding.clone(), <Vector>entry.embedding)
                order by similarity descending
                limit self.topK
                select {chunk: entry.chunk, embedding: entry.embedding, similarityScore: similarity};
            return sorted.clone();
        }
    }

    private isolated function calculateSimilarity(Vector queryEmbedding, Vector entryEmbedding) returns float {
        match self.similarityMetric {
            COSINE => {
                return vector:cosineSimilarity(queryEmbedding, entryEmbedding);
            }
            EUCLIDEAN => {
                return vector:euclideanDistance(queryEmbedding, entryEmbedding);
            }
            DOT_PRODUCT => {
                return vector:dotProduct(queryEmbedding, entryEmbedding);
            }
        }
        return vector:cosineSimilarity(queryEmbedding, entryEmbedding);
    }

    # Deletes a vector entry from the in-memory store.
    # Removes the entry that matches the given reference ID.
    #
    # + id - The reference ID of the vector entry to delete
    # + return - `ai:Error` if the reference ID is not found, otherwise `nil`
    public isolated function delete(string id) returns Error? {
        lock {
            int? indexToRemove = ();
            foreach int i in 0 ..< self.entries.length() {
                if self.entries[i].id == id {
                    indexToRemove = i;
                    break;
                }
            }

            if indexToRemove is () {
                return error Error(string `Vector entry with reference id '${id}' not found`);
            }
            _ = self.entries.remove(indexToRemove);
        }
    }
}
