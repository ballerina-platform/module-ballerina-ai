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

final Wso2ModelProvider? defaultModelProvider;
final Wso2EmbeddingProvider? defaultEmbeddingProvider;

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
    # + documents - The documents or chunks to index
    # + return - An `ai:Error` if indexing fails; otherwise, `nil`
    public isolated function ingest(Chunk[]|Document[]|Document documents) returns Error?;

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
    private final Chunker|AUTO|DISABLE chunker;

    # Initializes a new `VectorKnowledgeBase` instance.
    #
    # + vectorStore - The vector store for embedding persistence
    # + embeddingModel - The embedding provider for generating vector representations
    # + chunker - The chunker to chunk the documents. If set to `AUTO`, the chunker will be chosen automatically
    # based on the document type. If set to `DISABLE`, no chunking will be performed.
    # Otherwise, the specified chunker will be used.
    public isolated function init(VectorStore vectorStore, EmbeddingProvider embeddingModel,
            Chunker|AUTO|DISABLE chunker = AUTO) {
        self.vectorStore = vectorStore;
        self.embeddingModel = embeddingModel;
        self.retriever = new VectorRetriever(vectorStore, embeddingModel);
        self.chunker = chunker;
    }

    # Indexes a collection of chunks.
    # Converts each chunk to an embedding and stores it in the vector store,
    # making the chunk searchable through the retriever.
    #
    # + documents - The documents or chunks to be indexed.
    # The configured chunker will further split any provided documents or chunks before indexing.
    # + return - An `ai:Error` if indexing fails; otherwise, `nil`
    public isolated function ingest(Document|Document[]|Chunk[] documents) returns Error? {
        Chunk[] chunks = check self.chunk(documents);
        Embedding[] embeddings = check self.embeddingModel->batchEmbed(chunks);
        if chunks.length() != embeddings.length() {
            return error Error("Mismatch between number of chunks and embeddings generated");
        }
        VectorEntry[] entries = from [int, Chunk] [i, chunk] in chunks.enumerate()
            select {chunk, embedding: embeddings[i]};
        check self.vectorStore.add(entries);
    }

    private isolated function chunk(Document|Document[]|Chunk[] input) returns Chunk[]|Error {
        (Document|Chunk)[] inputs = input is Document[]|Chunk[] ? input : [input];
        Chunker|AUTO|DISABLE chunker = self.chunker;
        if chunker is DISABLE {
            return inputs;
        }
        Chunk[] chunks = [];
        foreach Document|Chunk item in inputs {
            Chunker chunkerToUse = chunker is Chunker ? chunker : guessChunker(item);
            chunks.push(...check chunkerToUse.chunk(item));
        }
        return chunks;
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

isolated function guessChunker(Document|Chunk doc) returns Chunker {
    // Guess the chunker based on the document type or mimeType in metadata
    string? fileName = doc.metadata?.fileName;
    if fileName is string && fileName.endsWith(".md") {
        return new MarkdownChunker();
    }
    return new GenericRecursiveChunker();
}

# Creates a default model provider based on the provided `wso2ProviderConfig`.
# + return - A `Wso2ModelProvider` instance if the configuration is valid; otherwise, an `ai:Error`.
public isolated function getDefaultModelProvider() returns Wso2ModelProvider|Error {
    if defaultModelProvider is () {
        return error Error("The `ballerina.ai.wso2ProviderConfig` is not configured correctly."
            + " Ensure values are configured for the WSO2 model provider configurable variable");
    }

    return <Wso2ModelProvider>defaultModelProvider;
}

# Creates a default embedding provider based on the provided `wso2ProviderConfig`.
# + return - A `Wso2EmbeddingProvider` instance if the configuration is valid; otherwise, an `ai:Error`.
public isolated function getDefaultEmbeddingProvider() returns Wso2EmbeddingProvider|Error {
    if defaultEmbeddingProvider is () {
        return error Error("The `ballerina.ai.wso2ProviderConfig` is not configured correctly."
            + " Ensure values are configured for the WSO2 embedding provider configurable variable");
    }

    return <Wso2EmbeddingProvider>defaultEmbeddingProvider;
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
