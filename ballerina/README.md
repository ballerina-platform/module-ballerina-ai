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

Ballerina offers several model providers available on [Ballerina Central](https://central.ballerina.io/search?q=module-ballerinax-ai.&sort=relevance%2CDESC&page=1&m=packages).
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

AI Agents are intelligent entities that can reason, plan, and perform complex tasks by leveraging LLMs along with tools and external data sources. They go beyond single-turn interactions by maintaining context, making decisions, and executing actions autonomously or semi-autonomously based on user instructions. Follow these steps to create an AI Agent using the `ballerina/ai` module.

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
TaskManagerToolkit taskManagerTools = new ();
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
    tools = [sum, mult, taskManagerTools], // Pass an array of function pointers annotated with @ai:AgentTool
    memory = memory
);
```

### 2.7 Invoke the Agent

Finally, invoke the agent by calling the `run` method:

```ballerina
mathTutorAgent.run("What is 8 + 9 multiplied by 10", sessionId = "student-one");
```

## Examples

The `ai` module provides practical examples illustrating usage in various scenarios. Explore these [examples](https://github.com/ballerina-platform/module-ballerina-ai/tree/main/examples/), covering the following use cases:

1. [Personal AI Assistant](https://github.com/ballerina-platform/module-ballerina-ai/tree/main/examples/personal-ai-assistant) - Demonstrates how to implement a personal AI assistant using Ballerina AI module along with Google Calendar and Gmail integrations
