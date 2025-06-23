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

# Represents document retriever that finds relevant documents based on query similarity.
public type Retriever distinct isolated object {
    # Retrieves relevant documents for the given query.
    #
    # + query - The text query to search for
    # + filters - Optional metadata filters to apply during retrieval
    # + return - An array of matching documents with similarity scores, or an `Error` if retrieval fails
    public isolated function retrieve(string query, MetadataFilters? filters = ()) returns DocumentMatch[]|Error;
};

# Represents document retriever that finds relevant documents based on query similarity.
# The `Retriever` combines query embedding generation and vector search
# to return matching documents along with their similarity scores.
public distinct isolated class VectorRetriever {
    *Retriever;
    private final VectorStore vectorStore;
    private final EmbeddingProvider embeddingModel;

    # Initializes a new `Retriever` instance.
    #
    # + vectorStore - The vector store to search in.
    # + embeddingModel - The embedding provider to use for generating query embeddings
    public isolated function init(VectorStore vectorStore, EmbeddingProvider embeddingModel) {
        self.vectorStore = vectorStore;
        self.embeddingModel = embeddingModel;
    }

    # Retrieves relevant documents for the given query.
    #
    # + query - The text query to search for
    # + filters - Optional metadata filters to apply during retrieval
    # + return - An array of matching documents with similarity scores, or an `Error` if retrieval fails
    public isolated function retrieve(string query, MetadataFilters? filters = ()) returns DocumentMatch[]|Error {
        Embedding queryEmbedding = check self.embeddingModel->embed({content: query});
        VectorStoreQuery vectorStoreQuery = {
            embedding: queryEmbedding,
            filters: filters
        };
        VectorMatch[] matches = check self.vectorStore.query(vectorStoreQuery);
        return from VectorMatch 'match in matches
            select {document: 'match.document, similarityScore: 'match.similarityScore};
    }
}

# Represents a knowledge base for managing document indexing and retrieval operations.
public type KnowledgeBase distinct isolated object {
    # Indexes a collection of documents.
    #
    # + documents - The array of documents to index
    # + return - An `Error` if indexing fails; otherwise, `nil`
    public isolated function index(Document[] documents) returns Error?;

    # Returns the retriever for this knowledge base.
    #
    # + return - The `Retriever` instance for performing document searches
    public isolated function getRetriever() returns Retriever;
};

# Represents a vector knowledge base for managing document indexing and retrieval operations.
# The `VectorKnowledgeBase` handles converting documents to embeddings,
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

    # Indexes a collection of documents.
    # Converts each document to an embedding and stores it in the vector store,
    # making the documents searchable through the retriever.
    #
    # + documents - The array of documents to index
    # + return - An `Error` if indexing fails; otherwise, `nil`
    public isolated function index(Document[] documents) returns Error? {
        VectorEntry[] entries = [];
        foreach Document document in documents {
            Embedding embedding = check self.embeddingModel->embed(document);
            entries.push({embedding, document});
        }
        check self.vectorStore.add(entries);
    }

    # Returns the retriever for this knowledge base.
    #
    # + return - The `Retriever` instance for performing document searches
    public isolated function getRetriever() returns Retriever {
        return self.retriever;
    }
}

# Orchestrates a Retrieval-Augmented Generation (RAG) pipeline.
# The `Rag` class manages document retrieval, prompt construction, and language model interaction
# to generate context-aware responses to user queries.
public distinct isolated class Rag {
    private final ModelProvider model;
    private final KnowledgeBase knowledgeBase;
    private final RagPromptTemplate promptTemplate;

    # Creates a new `Rag` instance.
    #
    # + model - The large language model used by the RAG pipeline. If `nil`, `Wso2ModelProvider` is used as the default
    # + knowledgeBase - The knowledge base containing indexed documents.
    # If `nil`, a default `VectorKnowledgeBase` is created, backed by `InMemoryVectorStore` and `Wso2EmbeddingProvider`
    # + promptTemplate - The RAG prompt template used by the language model to construct context-aware prompts.
    # Defaults to `DefaultRagPromptTemplate` if not provided
    # + return - `nil` on success, or an `Error` if initialization fails
    public isolated function init(ModelProvider? model = (),
            KnowledgeBase? knowledgeBase = (),
            RagPromptTemplate promptTemplate = new DefaultRagPromptTemplate()) returns Error? {
        self.model = model ?: check getDefaultModelProvider();
        self.knowledgeBase = knowledgeBase ?: check getDefaultKnowledgeBase();
        self.promptTemplate = promptTemplate;
    }

    # Executes a query through the RAG pipeline.
    # Retrieves context documents, builds a prompt, and generates a model response.
    #
    # + query - The user’s input question or query.
    # + filters - Optional metadata filters for document retrieval.
    # + return - The generated response, or an `Error` if the operation fails.
    public isolated function query(string query, MetadataFilters? filters = ()) returns string|Error {
        DocumentMatch[] context = check self.knowledgeBase.getRetriever().retrieve(query, filters);
        Prompt prompt = self.promptTemplate.format(context.'map(ctx => ctx.document), query);
        ChatMessage[] messages = self.mapPromptToChatMessages(prompt);
        ChatAssistantMessage response = check self.model->chat(messages, []);
        return response.content ?: error Error("Unable to obtain valid answer");
    }

    # Ingests documents into the knowledge base.
    # Processes and indexes documents to make them searchable for future queries.
    #
    # + documents - Array of documents to ingest
    # + return - `nil` on success; `Error` if ingestion fails 
    public isolated function ingest(Document[] documents) returns Error? {
        return self.knowledgeBase.index(documents);
    }

    private isolated function mapPromptToChatMessages(Prompt prompt) returns ChatMessage[] {
        string? systemPrompt = prompt?.systemPrompt;
        string? userPrompt = prompt?.userPrompt;
        ChatMessage[] messages = [];
        if systemPrompt is string {
            messages.push({role: SYSTEM, content: systemPrompt});
        }
        if userPrompt is string {
            messages.push({role: USER, content: userPrompt});
        }
        return messages;
    }
}

isolated function getDefaultModelProvider() returns Wso2ModelProvider|Error {
    Wso2ProviderConfig? config = wso2ProviderConfig;
    if config is () {
        return error Error("The `wso2ProviderConfig` is not configured correctly."
        + " Ensure that the WSO2 model provider configuration is defined in your TOML file.");
    }
    return new Wso2ModelProvider(config);
}

isolated function getDefaultKnowledgeBase() returns VectorKnowledgeBase|Error {
    Wso2ProviderConfig? config = wso2ProviderConfig;
    if config is () {
        return error Error("The `wso2ProviderConfig` is not configured correctly."
        + " Ensure that the WSO2 model provider configuration is defined in your TOML file.");
    }
    EmbeddingProvider|Error wso2EmbeddingProvider = new Wso2EmbeddingProvider(config);
    if wso2EmbeddingProvider is Error {
        return error Error("error creating default vector knowledge base");
    }
    return new VectorKnowledgeBase(new InMemoryVectorStore(), wso2EmbeddingProvider);
}
