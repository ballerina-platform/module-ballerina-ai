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

isolated Wso2ModelProvider? defaultModelProvider = ();
isolated Wso2EmbeddingProvider? defaultEmbeddingProvider = ();

# Represents chunk retriever that finds relevant chunks based on query similarity.
public type Retriever distinct isolated object {
    # Retrieves relevant chunks for the given query.
    #
    # + query - The text query to search for
    # + filters - Optional metadata filters to apply during retrieval
    # + return - An array of matching chunks with similarity scores, or an `ai:Error` if retrieval fails
    public isolated function retrieve(string query, MetadataFilters? filters = ()) returns QueryMatch[]|Error;
};

# Represents a retriever that finds relevant chunks based on query similarity.
# The `Retriever` combines query embedding generation and vector search
# to return matching chunks along with their similarity scores.
public distinct isolated class VectorRetriever {
    *Retriever;
    private final VectorStore vectorStore;
    private final EmbeddingProvider embeddingModel;

    # Initializes a new `Retriever` instance.
    #
    # + vectorStore - The vector store to search in
    # + embeddingModel - The embedding provider to use for generating query embeddings
    public isolated function init(VectorStore vectorStore, EmbeddingProvider embeddingModel) {
        self.vectorStore = vectorStore;
        self.embeddingModel = embeddingModel;
    }

    # Retrieves relevant chunks for the given query.
    #
    # + query - The text query to search for
    # + filters - Optional metadata filters to apply during retrieval
    # + return - An array of matching chunks with similarity scores, or an `ai:Error` if retrieval fails
    public isolated function retrieve(string query, MetadataFilters? filters = ()) returns QueryMatch[]|Error {
        TextChunk queryChunk = {content: query, 'type: "text-chunk"};
        Embedding queryEmbedding = check self.embeddingModel->embed(queryChunk);
        VectorStoreQuery vectorStoreQuery = {
            embedding: queryEmbedding,
            filters
        };
        VectorMatch[] matches = check self.vectorStore.query(vectorStoreQuery);
        return from VectorMatch {chunk, similarityScore} in matches
            select {chunk, similarityScore};
    }
}

# Represents a knowledge base for managing chunk indexing and retrieval operations.
public type KnowledgeBase distinct isolated object {
    # Ingests a collection of chunks.
    #
    # + chunks - The array of chunk to index
    # + return - An `ai:Error` if indexing fails; otherwise, `nil`
    public isolated function ingest(Chunk[] chunks) returns Error?;

    # Retrieves relevant chunks for the given query.
    #
    # + query - The text query to search for
    # + filters - Optional metadata filters to apply during retrieval
    # + return - An array of matching chunks with similarity scores, or an `ai:Error` if retrieval fails
    public isolated function retrieve(string query, MetadataFilters? filters = ()) returns QueryMatch[]|Error;
};

# Represents a vector knowledge base for managing chunk indexing and retrieval operations.
# The `VectorKnowledgeBase` handles converting chunks to embeddings,
# storing them in a vector store, and enabling retrieval through a `Retriever`.
public distinct isolated class VectorKnowledgeBase {
    *KnowledgeBase;
    private final VectorStore vectorStore;
    private final EmbeddingProvider embeddingModel;
    private final Retriever retriever;

    # Initializes a new `VectorKnowledgeBase` instance.
    #
    # + vectorStore - The vector store for embedding persistence
    # + embeddingModel - The embedding provider for generating vector representations
    public isolated function init(VectorStore vectorStore, EmbeddingProvider embeddingModel) {
        self.vectorStore = vectorStore;
        self.embeddingModel = embeddingModel;
        self.retriever = new VectorRetriever(vectorStore, embeddingModel);
    }

    # Indexes a collection of chunks.
    # Converts each chunk to an embedding and stores it in the vector store,
    # making the chunk searchable through the retriever.
    #
    # + chunks - The array of chunk to index
    # + return - An `ai:Error` if indexing fails; otherwise, `nil`
    public isolated function ingest(Chunk[] chunks) returns Error? {
        VectorEntry[] entries = from Chunk chunk in chunks
            let Embedding embedding = check self.embeddingModel->embed(chunk)
            select {embedding, chunk};
        check self.vectorStore.add(entries);
    }

    # Retrieves relevant chunk for the given query.
    #
    # + query - The text query to search for
    # + filters - Optional metadata filters to apply during retrieval
    # + return - An array of matching chunks with similarity scores, or an `ai:Error` if retrieval fails
    public isolated function retrieve(string query, MetadataFilters? filters = ()) returns QueryMatch[]|Error {
        return self.retriever.retrieve(query, filters);
    }
}

# Creates a default model provider based on the provided `wso2ProviderConfig`.
# + return - A `Wso2ModelProvider` instance if the configuration is valid; otherwise, an `ai:Error`.
public isolated function getDefaultModelProvider() returns Wso2ModelProvider|Error {
    if defaultModelProvider is () {
        return error Error("The `wso2ProviderConfig` is not configured correctly."
            + " Ensure that the WSO2 model provider configuration is defined in your Config.toml file.");
    }

    return <Wso2ModelProvider>defaultModelProvider;
}

# Creates a default embedding provider based on the provided `wso2ProviderConfig`.
# + return - A `Wso2EmbeddingProvider` instance if the configuration is valid; otherwise, an `ai:Error`.
public isolated function getDefaultEmbeddingProvider() returns Wso2EmbeddingProvider|Error {
    if defaultEmbeddingProvider is () {
        return error Error("The `wso2ProviderConfig` is not configured correctly."
            + " Ensure that the WSO2 embedding provider configuration is defined in your Config.toml file.");
    }

    return <Wso2EmbeddingProvider>defaultEmbeddingProvider;
}

isolated function getDefaultKnowledgeBase() returns VectorKnowledgeBase|Error {
    Wso2ProviderConfig? config = wso2ProviderConfig;
    if config is () {
        return error Error("The `wso2ProviderConfig` is not configured correctly."
        + " Ensure that the WSO2 model provider configuration is defined in your TOML file.");
    }
    EmbeddingProvider|Error wso2EmbeddingProvider = new Wso2EmbeddingProvider(config.serviceUrl, config.accessToken);
    if wso2EmbeddingProvider is Error {
        return error Error("Error creating default vector knowledge base");
    }
    InMemoryVectorStore|Error inMemoryVectorStore = check new;
    if inMemoryVectorStore is Error {
        return error Error("Error creating default in-memory vector store", inMemoryVectorStore);
    }
    return new VectorKnowledgeBase(inMemoryVectorStore, wso2EmbeddingProvider);
}

# Augments the user's query with relevant context.
#
# + context - Array of matched chunks or documents to include as context
# + query - The user's original question
# + return - The augmented query with injected context
public isolated function augmentUserQuery(QueryMatch[]|Document[] context, string query) returns ChatUserMessage {
    Chunk[]|Document[] relevantContext = [];
    if context is QueryMatch[] {
        relevantContext = context.'map(queryMatch => queryMatch.chunk);
    } else if context is Document[] {
        relevantContext = context;
    }
    Prompt userPrompt = `Answer the question based on the following provided context:
    <CONTEXT>${relevantContext}</CONTEXT>
    
    Question: ${query}`;
    return {role: USER, content: userPrompt};
}
