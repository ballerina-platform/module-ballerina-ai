## Overview

This module provides APIs for building AI-powered applications and agents using Large Language Models (LLMs).

It includes capabilities for:

1. **Direct LLM Calls** – Interact directly with LLMs for tasks such as text generation, summarization, conversation, or structured output generation.
2. **AI Agents** – Create intelligent agents that can reason, plan, and use tools to perform complex tasks.
3. **Retrieval-Augmented Generation (RAG)** – Improve LLM outputs by incorporating information from your own data sources.

## 1. Direct LLM Calls

You can directly interact with Large Language Models (LLMs) using `ModelProvider` implementations.
The `ai:ModelProvider` type serves as a unified abstraction layer that enables integration with different LLMs through provider-specific modules such as `ballerinax/ai.openai`, `ballerinax/ai.anthropic`, and more.

Each model provider exposes two main high-level APIs:

- **`chat`** – Used for multi-turn conversational interactions.
- **`generate`** – Used for single-turn text generation with structured output generation.

Ballerina offers several model providers available on [Ballerina Central](https://central.ballerina.io/search?q=model+provider&sort=relevance%2CDESC&page=1&m=packages).
You can also implement your own custom provider if required.

Before using a model provider, you must first initialize it.

### 1.1 Initializing a Model Provider

For example, you can initialize a specific model provider such as OpenAI as shown below:

```ballerina
import ballerina/ai;
import ballerinax/ai.openai;

final ai:ModelProvider model = check new openai:ModelProvider("openAiApiKey", modelType = openai:GPT_4O);
```

### 1.2 Multi-turn Conversation with `chat`

The `chat` method is used for conversational interactions with an LLM.
It can take either a single user message or an array of messages:
- When you pass **a single message**, the interaction is **stateless** — the model does not have any prior context.
- When you pass **an array of messages**, the interaction is **context-aware** — the model considers the full conversation history to generate a coherent response.

```ballerina
public function main(string subject) returns error? {
    // Create a user message with the prompt as the content.
    ai:ChatUserMessage userMessage = {
        role: ai:USER,
        content: `Tell me a joke about ${subject}!`
    };

    // Use an array to hold the conversation history.
    ai:ChatMessage[] messages = [userMessage];

    // Use the `chat` method to make a call with the conversation history.
    // Alternatively, you can pass a single message (`userMessage`) too.
    ai:ChatAssistantMessage assistantMessage = check model->chat(messages);

    // Update the conversation history with the assistant's response.
    messages.push(assistantMessage);

    // Print the joke from the assistant's response.
    string? joke = assistantMessage?.content;
    io:println(joke);

    // Continue the conversation by asking for an explanation.
    messages.push({
        role: ai:USER,
        content: "Can you explain it?"
    });
    ai:ChatAssistantMessage assistantMessage2 = check model->chat(messages);

    // Since the conversation history is passed, the model can provide a relevant explanation.
    string? explanation = assistantMessage2?.content;
    io:println(explanation);
}
```

### 1.3 Single-Turn and Structured Output Generation with `generate`

The `generate` method allows you to perform single-turn text generation while producing structured outputs.
It accepts a natural language prompt, derives a JSON schema based on the provided type descriptor (i.e., the expected return type), sends the prompt to the LLM, and automatically maps the response to the expected type — enabling seamless integration between Ballerina types and LLM outputs.

```ballerina
type JokeResponse record {|
    string setup;
    string punchline;
|};

public function main(string subject) returns error? {
    // Use an insertion to insert the subject into the prompt.
    // The response is expected to be a string.
    string joke = check model->generate(`Tell me a joke about ${subject}!`);
    io:println(joke);

    // An LLM call with a structured response type.
    JokeResponse jokeResponse = check model->generate(`Tell me a joke about ${subject}!`);
    io:println("Setup: ", jokeResponse.setup);
    io:println("Punchline: ", jokeResponse.punchline);
}
```

## 2. AI Agents

AI Agents are intelligent entities that can reason, plan, and perform complex tasks by leveraging LLMs along with tools and external data sources. They go beyond single-turn interactions by maintaining context, making decisions, and executing actions autonomously or semi-autonomously based on user instructions. Follow these steps to create an AI Agent using the AI module.

### 2.1: Import the Module

Import the `ai` module:

```ballerina
import ballerina/ai;
```

### 2.2: Define the System Prompt

A system prompt guides the AI's behavior, tone, and response style, defining its role and interaction with users.

```ballerina
ai:SystemPrompt systemPrompt = {
    role: "Math Tutor",
    instructions: string `You are a helpful math tutor. Explain concepts clearly with examples and provide step-by-step solutions.`
};
```

### 2.3: Define the Model Provider

```ballerina
import ballerinax/ai.openai;

final openai:ModelProvider model = check new ("openAiApiKey", modelType = openai:GPT_4O);
```

To learn more about ModelProviders, see [Direct LLM calls](#1-direct-llm-calls).

### 2.4: Define Tools and Toolkits

An agent tools and toolkits extends the AI's abilities beyond text-based responses, enabling interaction with external systems or dynamic tasks. 

You can define basic tools as shown below
#### 2.4.1 Defining a Tool

```ballerina
# Returns the sum of two numbers
# + a - first number
# + b - second number
# + return - sum of the numbers
@ai:AgentTool
isolated function sum(int a, int b) returns int => a + b;

@ai:AgentTool
isolated function mult(int a, int b) returns int => a * b;
```

#### 2.4.1.1 Constraints for defining tools

1. The tool methods/functions must be marked `isolated` and annotated with `@ai:AgentTool`.
2. Parameters should be a subtype of `anydata`.
3. The tool should return a subtype of `anydata|http:Response|stream<anydata, error>|error`.
4. Tool documentation enhances LLM performance but is optional.

#### 2.4.2 Defining a Toolkit

A **toolkit** is a class that encapsulates related tools and their state. Toolkits are **recommended for building stateful tools**, where you need to maintain data across multiple calls by an AI agent. To define a toolkit:

##### 2.4.2.1 Define An Isolated Class

```ballerina
public isolated class TaskManagerToolkit {
}
```

##### 2.4.2.2 Include the `ai:BaseToolkit` Type

```ballerina
public isolated class TaskManagerToolkit {
    *ai:BaseToolkit;

    public isolated function getTools() returns ToolConfig[] {
        // TODO: implement tool mapping
    }
}
```

##### 2.4.2.3 Implement the Tools within the Toolkit

In this example, we define three tools — `addTask`, `getTask`, and `listTasks`.
The same constraints outlined in [Constraints for defining tools](#2411-constraints-for-defining-tools) apply here as well.

```ballerina
public isolated class TaskManagerToolkit {
    *ai:BaseToolkit;
    private final map<string> tasks = {};

    @ai:AgentTool
    public isolated function addTask(string description) {
        lock {
            self.tasks[generateUniqueId()] = description;
        }
    }

    @ai:AgentTool
    public isolated function getTask(string id) returns string? {
        lock {
            return self.tasks[id];
        }
    }

    @ai:AgentTool
    public isolated function listTasks() returns map<string> {
        lock {
            return self.tasks.clone();
        }
    }

    public isolated function getTools() returns ToolConfig[] {
        // TODO: implement tool mapping
    }
}
```

##### 2.4.1.4 Implement `getTools()` Method

```ballerina
public isolated class TaskManagerToolkit {
    *ai:BaseToolkit;
    private final map<string> tasks = {};

    @ai:AgentTool
    public isolated function addTask(string description) {
        // omitted for brevity
    }

    @ai:AgentTool
    public isolated function getTask(string id) returns string? {
        // omitted for brevity
    }

    @ai:AgentTool
    public isolated function listTasks() returns map<string> {
        // omitted for brevity
    }

    public isolated function getTools() returns ToolConfig[] => 
        ai:getToolConfigs([self.addTask, self.getTask, self.listTasks]);
}
```

**Note:** `ai:getToolConfigs` is a utility method provided by the AI module that converts function pointers into their corresponding `ai:ToolConfig` records.

##### 2.4.1.5 Initialize the toolkit

```ballerina
TaskManagerToolkit taskManagerTools = new;
```

Now the `taskManagerTools` instance can be passed to an AI agent, enabling **stateful task management** through its tools.

### 2.5 Define the Memory

The `ai` module manages memory for individual user sessions using `Memory`. By default, agents are configured with memory that has a predefined capacity. To create a stateless agent, set `memory` to `()` when defining the agent. You can also customize the memory capacity or provide your own memory implementation. Example:

```ballerina
final ai:Memory memory = check new ai:ShortTermMemory(check new ai:InMemoryShortTermMemoryStore(15));
```

### 2.6 Define the Agent

Create a Ballerina AI agent using the configurations defined earlier:

```ballerina
final ai:Agent mathTutorAgent = check new (
    systemPrompt = systemPrompt,
    model = model,
    tools = [sum, mult, taskManagerTools], // Provide an array of function pointers and toolkit instances
    memory = memory
);
```

### 2.7 Invoke the Agent

Finally, invoke the agent by calling the `run` method:

```ballerina
mathTutorAgent.run("What is 8 + 9 multiplied by 10", sessionId = "student-one");
```

## 3. Retrieval-Augmented Generation

Retrieval-Augmented Generation (RAG) enables LLMs to improve responses by fetching relevant information from an external knowledge base. Typically, RAG consist of two main flows:

1. **Ingestion Flow** – Adding knowledge or data to the system.
2. **Retrieval Flow** – Querying the stored knowledge to enhance LLM responses.  

The AI module provides a high-level abstraction called **KnowledgeBase** to make both flows simple. It offers the following APIs:  
- `ingest` – Add data or knowledge to the KnowledgeBase.  
- `retrieve` – Search and retrieve relevant knowledge.  
- `deleteByFilter` – Remove specific entries based on filters.  

In a typical RAG system, the KnowledgeBase is often backed by a vector database for efficient storage and retrieval. The AI module provides **`ai:VectorKnowledgeBase`**, which uses an **`ai:VectorStore`** to implement this functionality.
You can also create a custom KnowledgeBase if your requirements differ. 

In oder to write a RAG workflow you should initialize the Knowledge base.

### 3.1 Creating a Vector Knowledge Base

To create a `ai:VectorKnowledgeBase`, you need both an embedding model and a vector database.
The embedding model can be obtained via an `ai:EmbeddingProvider` implementation, and the vector database can be set up using an `ai:VectorStore` implementation. Follow the steps below to initialize the embedding model and vector store.

### 3.1.1: Initialize the Embedding Provider

The `ai:EmbeddingProvider` transforms documents into embeddings during **ingestion** and converts user queries into embeddings for **similarity searches** against your database vectors during **retrieval**. The AI library provides this as an abstraction, with multiple provider implementations available on [Ballerina Central](https://central.ballerina.io/search?q=%22ai.openai%22+%22ai.azure%22+embedding+provider&sort=relevance%2CDESC&page=1&m=packages), so you can choose the provider that best fits your use case:


```ballerina
import ballerina/ai.openai;

final openai:EmbeddingProvider embeddingModel = check new ("openAiApiKey", openapi:TEXT_EMBEDDING_3_SMALL);
```

### 3.1.2: Initialize a Vector Store

A Vector Store is an abstraction provided by the `ai` module to index and retrieve data from a database. Multiple vector store implementations are available on [Ballerina Central](https://central.ballerina.io/search?q=vector+store+%22ai.%22&sort=relevance%2CDESC&page=1&m=packages), such as Pinecone, Weaviate, PGVector, Milvus, or an in-memory store for testing:

```ballerina
import ballerina/ai.pinecone;

final pinecone:VectorStore vectorStore = check new ("pineconeServiceUrl", "pineconeApiKey");
```

### 3.1.3: Initialize the Vector Knowledge Base

Once you have the embedding model and vector store, initialize the `VectorKnowledgeBase`:

```ballerina
final ai:KnowledgeBase knowledgeBase = new ai:VectorKnowledgeBase(vectorStore, embeddingModel);
```

### 3.2 Implementing an Ingestion Workflow

The following is an example of a typical ingestion workflow, where text documents are loaded from files. This example uses `ai:TextDataLoader` provided by the AI module to load documents as `ai:Document`s - a common document format abstraction provided by the module. The loaded documents are then ingested into the knowledge base.

```ballerina
public function main() returns error? {
    // Initialize the data loader to load documents from a file or folder
    ai:DataLoader loader = check new ai:TextDataLoader("./leave_policy.md");

    // Load the documents using the data loader
    ai:Document|ai:Document[] documents = check loader.load();

    // Ingest the documents into the knowledge base.
    // The knowledge base handles chunking automatically during ingestion.
    // For more control, you can manually chunk the documents using
    // `ai:Chunker` implementations and pass the chunks instead.
    check knowledgeBase.ingest(documents);

    io:println("Ingestion successful");
}
```

### 3.3 Implementing a Retrieval Workflow

The following example demonstrates a typical retrieval workflow, where a user query is matched against documents in the knowledge base, augmented using the `ai:augmentUserQuery` utility method from the AI module, and then sent to the model (a ModelProvider instance) for generating a response.

```ballerina
string appealQuery = "How many annual leave days can a full-time employee carry forward to the next year?";

// Retrieve relevant top 10 chunks from the knowledge base
ai:QueryMatch[] queryMatches = check knowledgeBase.retrieve(appealQuery, 10);

// Augment the user query using the retrieved documents
ai:ChatUserMessage augmentedQuery = ai:augmentUserQuery(context, appealQuery);

// Send the augmented query to the model for response generation
ai:ChatAssistantMessage assistantMessage = check model->chat(augmentedQuery);

// Print the assistant's answer
io:println("Answer: ", assistantMessage.content);
```

## Examples

The `ai` module provides practical examples illustrating usage in various scenarios. Explore these [examples](https://github.com/ballerina-platform/module-ballerina-ai/tree/main/examples/), covering the following use cases:

1. [Personal AI Assistant](https://github.com/ballerina-platform/module-ballerina-ai/tree/main/examples/personal-ai-assistant) - Demonstrates how to implement a personal AI assistant using Ballerina AI module along with Google Calendar and Gmail integrations
