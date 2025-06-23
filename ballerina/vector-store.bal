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

# An in-memory vector store implementation that provides simple storage for vector entries.
public isolated class InMemoryVectorStore {
    *VectorStore;
    private final VectorEntry[] entries = [];
    private final int topK;

    # Initializes a new in-memory vector store.
    #
    # + topK - The maximum number of top similar vectors to return in query results
    public isolated function init(int topK = 3) {
        self.topK = topK;
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
    # Uses cosine similarity for dense vector comparison and returns the top-K results.
    #
    # + query - The query containing the embedding vector and optional filters
    # + return - An array of vector matches sorted by similarity score (limited to topK), 
    # or an `Error` if the query fails
    public isolated function query(VectorStoreQuery query) returns VectorMatch[]|Error {
        if query.embedding !is Vector {
            return error Error("InMemoryVectorStore supports dense vectors exclusively");
        }

        lock {
            VectorMatch[] sorted = from var entry in self.entries
                let float similarity = self.cosineSimilarity(<Vector>query.embedding.clone(), <Vector>entry.embedding)
                order by similarity descending
                limit self.topK
                select {document: entry.document, embedding: entry.embedding, similarityScore: similarity};
            return sorted.clone();
        }
    }

    # Deletes a vector entry from the in-memory store.
    # Removes the entry that matches the given reference ID.
    #
    # + id - The reference ID of the vector entry to delete
    # + return - `Error` if the reference ID is not found, otherwise `nil`
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
                return error Error(string `Vector entry with reference ID '${id}' not found`);
            }
            _ = self.entries.remove(indexToRemove);
        }
    }

    private isolated function cosineSimilarity(Vector a, Vector b) returns float {
        if a.length() != b.length() {
            return 0.0;
        }

        float dot = 0.0; // Dot product
        float normA = 0.0; // Norm of vector A
        float normB = 0.0; // Norm of vector B

        foreach int i in 0 ..< a.length() {
            dot += a[i] * b[i];
            normA += a[i] * a[i];
            normB += b[i] * b[i];
        }

        float denom = normA.sqrt() * normB.sqrt();
        return denom == 0.0 ? 0.0 : dot / denom;
    }
}
