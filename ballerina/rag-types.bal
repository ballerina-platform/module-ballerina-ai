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

# Represents a dense vector with floating-point values.
public type Vector float[];

# Represents a sparse vector storing only non-zero values with their corresponding indices.
#
# + indices - Array of indices where non-zero values are located 
# + values - Array of non-zero floating-point values corresponding to the indices
public type SparseVector record {|
    int[] indices;
    Vector values;
|};

# Represents a hybrid embedding containing both dense and sparse vector representations.
#
# + dense - Dense vector representation of the embedding
# + sparse - Sparse vector representation of the embedding
public type HybridVector record {|
    Vector dense;
    SparseVector sparse;
|};

# Represents possible vector types.
public type Embedding Vector|SparseVector|HybridVector;

# Represents the set of supported operators used for metadata filtering during vector search operations.
public enum MetadataFilterOperator {
    EQUAL = "==",
    NOT_EQUAL = "!=",
    GREATER_THAN = ">",
    LESS_THAN = "<",
    GREATER_THAN_OR_EQUAL = ">=",
    LESS_THAN_OR_EQUAL = "<=",
    IN = "in",
    NOT_IN = "nin"
}

# Represents logical conditions for combining multiple metadata filtering during vector search operations.
public enum MetadataFilterCondition {
    AND = "and",
    OR = "or"
}

# Represents a metadata filter for vector search operations.
# Defines conditions to filter vectors based on their associated metadata values.
#
# + key - The name of the metadata field to filter
# + operator - The comparison operator to use. Defaults to `EQUAL`
# + value - - The value to compare the metadata field against
public type MetadataFilter record {|
    string key;
    MetadataFilterOperator operator = EQUAL;
    json value;
|};

# Represents a container for combining multiple metadata filters using logical operators.
# Enables complex filtering by applying multiple conditions with AND/OR logic during vector search.
#
# + filters - An array of `MetadataFilter` or nested `MetadataFilters` to apply.
# + condition - The logical operator (`AND` or `OR`) used to combine the filters. Defaults to `AND`.
public type MetadataFilters record {|
    (MetadataFilters|MetadataFilter)[] filters;
    MetadataFilterCondition condition = AND;
|};

# Defines a query to the vector store with an embedding vector and optional metadata filters.
# Supports precise search operations by combining vector similarity with metadata conditions.
#
# + embedding - The vector to use for similarity search.
# + filters - Optional metadata filters to refine the search results.
public type VectorStoreQuery record {|
    Embedding embedding;
    MetadataFilters filters?;
|};

# Represents a document with content and optional metadata.
#
# + content - The main text content of the document
# + metadata - Optional key-value pairs that provide additional information about the document
public type Document record {|
    string content;
    map<anydata> metadata?;
|};

# Represents a vector entry combining an embedding with its source document.
#
# + id - Optional unique identifier for the vector entry
# + embedding - The vector representation of the document content
# + document - The original document associated with the embedding
public type VectorEntry record {|
    string id?;
    Embedding embedding;
    Document document;
|};

# Represents a vector match result with similarity score.
#
# + similarityScore - Similarity score indicating how closely the vector matches the query 
public type VectorMatch record {|
    *VectorEntry;
    float similarityScore;
|};

# Represents query modes to be used with vector store.
# Defines different search strategies for retrieving relevant documents
# based on the type of embeddings and search algorithms to be used.
public enum VectorStoreQueryMode {
    DENSE,
    SPARSE,
    HYBRID
}

# Represents a document match result with similarity score.
#
# + document - The matched document
# + similarityScore - Similarity score indicating document relevance to the query
public type DocumentMatch record {|
    Document document;
    float similarityScore;
|};

# Represents a prompt constructed by `RagPromptTemplate` object.
#
# + systemPrompt - System-level instructions that given to a Large Language Model
# + userPrompt - The user's question or query given to the Large Language Model
public type Prompt record {|
    string systemPrompt?;
    string userPrompt;
|};
