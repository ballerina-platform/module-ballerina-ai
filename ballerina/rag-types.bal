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
public type SparseVector record {|
    # Array of indices where non-zero values are located 
    int[] indices;
    # Array of non-zero floating-point values corresponding to the indices
    Vector values;
|};

# Represents a hybrid embedding containing both dense and sparse vector representations.
public type HybridVector record {|
    # Dense vector representation of the embedding
    Vector dense;
    # Sparse vector representation of the embedding
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
public type MetadataFilter record {|
    # The name of the metadata field to filter
    string key;
    # The comparison operator to use. Defaults to `EQUAL`
    MetadataFilterOperator operator = EQUAL;
    # The value to compare the metadata field against
    json value;
|};

# Represents a container for combining multiple metadata filters using logical operators.
# Enables complex filtering by applying multiple conditions with AND/OR logic during vector search.
public type MetadataFilters record {|
    # An array of `MetadataFilter` or nested `MetadataFilters` to apply
    (MetadataFilters|MetadataFilter)[] filters;
    # The logical operator (`AND` or `OR`) used to combine the filters. Defaults to `AND`
    MetadataFilterCondition condition = AND;
|};

# Defines a query to the vector store with an embedding vector and optional metadata filters.
# Supports precise search operations by combining vector similarity with metadata conditions.
public type VectorStoreQuery record {|
    # The vector to use for similarity search
    Embedding embedding;
    # Optional metadata filters to refine the search results.
    MetadataFilters filters?;
|};

# Represents a vector entry combining an embedding with its source chunk. 
public type VectorEntry record {|
    # Optional unique identifier for the vector entry
    string id?;
    # The vector representation of the chunk content
    Embedding embedding;
    # The chunk associated with the embedding
    Chunk chunk;
|};

# Represents a vector match result with similarity score. 
public type VectorMatch record {|
    *VectorEntry;
    # Similarity score indicating how closely the vector matches the query
    float similarityScore;
|};

# Represents query modes to be used with vector store.
# Defines different search strategies for retrieving relevant chunks
# based on the type of embeddings and search algorithms to be used.
public enum VectorStoreQueryMode {
    # Uses dense vector embeddings for similarity search
    DENSE,
    # Uses sparse vector embeddings for similarity search
    SPARSE,
    # Uses hybrid embeddings that combine dense and sparse representations
    HYBRID
}

# Represents a match result with similarity score.
public type QueryMatch record {|
    # The chunk that matched the query
    Chunk chunk;
    # Similarity score indicating chunk relevance to the query
    float similarityScore;
|};

# Represents the similarity metrics used for comparing vectors.
# Defines how the similarity between vectors is calculated during search operations.
public enum SimilarityMetric {
    # Cosine similarity measures the cosine of the angle between two vectors
    COSINE,
    # Euclidean distance calculates the straight-line distance between two points in space
    EUCLIDEAN,
    # Reflect the directional similarity between two vectors
    DOT_PRODUCT
}

type InMemoryVectorEntry record {|
    *VectorEntry;
    readonly string id;
|};
