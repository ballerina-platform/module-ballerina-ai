## Overview

This module offers APIs for developing AI applications and agents powered by Large Language Models (LLMs).

AI agents use LLMs to process natural language inputs, generate responses, and make decisions based on given instructions. These agents can be designed for various tasks, such as answering questions, automating workflows, or interacting with external systems.

## Quickstart

To use the `ai` module in your Ballerina application, update the `.bal` file as follows:

### Step 1: Import the module

Import the `ai` module.

```ballerina
import ballerina/ai;
```

### Step 2: Define the System Prompt

A system prompt guides the AI's behavior, tone, and response style, defining its role and interaction with users.

```ballerina
ai:SystemPrompt systemPrompt = {
    role: "Math Tutor",
    instructions: string `You are a helpful math tutor. Explain concepts clearly with examples and provide step-by-step solutions.`
};
```

### Step 3: Define the Model Provider

Ballerina currently supports multiple model providers, which you can explore [here on Ballerina Central](https://central.ballerina.io/search?q=module-ballerinax-ai.model.provider.&sort=relevance%2CDESC&page=1&m=packages).

In addition to these prebuilt implementations, you also have the flexibility to implement your own custom provider.

Here's how to initialize the prebuilt OpenAI model provider:

```ballerina
import ballerinax/ai.model.provider.openai;

final ai:ModelProvider openAiModel = check new openai:Provider("openAiApiKey", modelType = openai:GPT_4O);
```

### Step 4: Define the tools

An agent tool extends the AI's abilities beyond text-based responses, enabling interaction with external systems or dynamic tasks. Define tools as shown below:

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

Constraints for defining tools:

1. The function must be marked `isolated`.
2. Parameters should be a subtype of `anydata`.
3. The tool should return a subtype of `anydata|http:Response|stream<anydata, error>|error`.
4. Tool documentation enhances LLM performance but is optional.

### Step 5: Define the Memory

The `ai` module manages memory for individual user sessions using the `Memory`. By default, agents are configured with a memory that has a predefined capacity. To create a stateless agent, set the `memory` to `()` when defining the agent. Additionally, you can customize the memory capacity or provide your own memory implementation. Here's how to initialize the default memory with a new capacity:

```ballerina
final ai:Memory memory = new ai:MessageWindowChatMemory(20);
```

### Step 6: Define the Agent

Create a Ballerina AI agent using the configurations created earlier:

```ballerina
final ai:Agent mathTutorAgent = check new (
    systemPrompt = systemPrompt,
    model = openAiModel,
    tools = [sum, mult], // Pass array of function pointers annotated with @ai:AgentTool
    memory = memory
);
```

### Step 7: Invoke the Agent

Finally, invoke the agent by calling the `run` method:

```ballerina
mathTutorAgent.run("What is 8 + 9 multiplied by 10", sessionId = "student-one");
```

If using the agent with a single session, you can omit the `sessionId` parameter.

## Examples

The `ai` module provides practical examples illustrating usage in various scenarios. Explore these [examples](https://github.com/ballerina-platform/module-ballerina-ai/tree/main/examples/), covering the following use cases:

1. [Personal AI Assistant](https://github.com/ballerina-platform/module-ballerina-ai/tree/main/examples/personal-ai-assistant) - Demonstrates how to implement a personal AI assistant using Ballerina AI module along with Google Calendar and Gmail integrations
