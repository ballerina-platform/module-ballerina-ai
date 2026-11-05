# Specification: Ballerina AI Library

_Owners_: @MohamedSabthar @shafreenAnfar @kalaiyarasiganeshalingam @RadCod3  
_Reviewers_: @MohamedSabthar @shafreenAnfar @kalaiyarasiganeshalingam @RadCod3  
_Created_: 2026/10/28  
_Updated_: 2026/11/05  
_Edition_: Swan Lake


## Introduction
This is the specification for the AI standard library of [Ballerina language](https://ballerina.io/), which provides the abstractions to build AI-powered applications: calling large language models (LLMs), building agents that use tools and memory, retrieval-augmented generation (RAG), and exposing agents as chat services.

The AI library specification has evolved and may continue to evolve in the future. The released versions of the specification can be found under the relevant GitHub tag.

If you have any feedback or suggestions about the library, start a discussion via a [GitHub issue](https://github.com/ballerina-platform/ballerina-library/issues) or in the [Discord server](https://discord.gg/ballerinalang). Based on the outcome of the discussion, the specification and implementation can be updated. Community feedback is always welcome. Any accepted proposal, which affects the specification is stored under `/docs/proposals`. Proposals under discussion can be found with the label `type/proposal` in GitHub.

The conforming implementation of the specification is released and included in the distribution. Any deviation from the specification is considered a bug.

## Contents

1. [Overview](#1-overview)
2. [Model providers](#2-model-providers)
    * 2.1. [ModelProvider](#21-modelprovider)
    * 2.2. [Chat messages](#22-chat-messages)
    * 2.3. [Chat](#23-chat)
    * 2.4. [Generate and prompt templates](#24-generate-and-prompt-templates)
        * 2.4.1. [Prompt](#241-prompt)
        * 2.4.2. [Structured output](#242-structured-output)
        * 2.4.3. [Generator configuration](#243-generator-configuration)
    * 2.5. [Default WSO2 model provider](#25-default-wso2-model-provider)
3. [Embedding providers](#3-embedding-providers)
    * 3.1. [EmbeddingProvider](#31-embeddingprovider)
    * 3.2. [Default WSO2 embedding provider](#32-default-wso2-embedding-provider)
4. [Tools](#4-tools)
    * 4.1. [Function tools](#41-function-tools)
        * 4.1.1. [Schema generation and constraints](#411-schema-generation-and-constraints)
    * 4.2. [Tool configuration](#42-tool-configuration)
    * 4.3. [Toolkits](#43-toolkits)
        * 4.3.1. [BaseToolKit](#431-basetoolkit)
        * 4.3.2. [MCP toolkit](#432-mcp-toolkit)
        * 4.3.3. [HTTP service toolkit](#433-http-service-toolkit)
            * 4.3.3.1. [Tools from OpenAPI specifications](#4331-tools-from-openapi-specifications)
    * 4.4. [Tool authorization](#44-tool-authorization)
    * 4.5. [Context](#45-context)
5. [Agents](#5-agents)
    * 5.1. [Agent configuration](#51-agent-configuration)
    * 5.2. [Running an agent](#52-running-an-agent)
    * 5.3. [Sessions](#53-sessions)
    * 5.4. [Execution loop](#54-execution-loop)
    * 5.5. [Human-in-the-loop approval](#55-human-in-the-loop-approval)
        * 5.5.1. [Approval rules](#551-approval-rules)
        * 5.5.2. [Pausing a run](#552-pausing-a-run)
        * 5.5.3. [Resuming a run](#553-resuming-a-run)
        * 5.5.4. [Checkpoints](#554-checkpoints)
    * 5.6. [Agent identity](#56-agent-identity)
    * 5.7. [Custom agents](#57-custom-agents)
    * 5.8. [Traces and evaluation](#58-traces-and-evaluation)
6. [Memory](#6-memory)
    * 6.1. [Memory type](#61-memory-type)
    * 6.2. [Short-term memory](#62-short-term-memory)
        * 6.2.1. [Trim overflow handling](#621-trim-overflow-handling)
        * 6.2.2. [Model-assisted overflow handling](#622-model-assisted-overflow-handling)
    * 6.3. [Short-term memory store](#63-short-term-memory-store)
    * 6.4. [Message window chat memory](#64-message-window-chat-memory)
7. [Retrieval-augmented generation](#7-retrieval-augmented-generation)
    * 7.1. [Documents and chunks](#71-documents-and-chunks)
    * 7.2. [Data loaders](#72-data-loaders)
    * 7.3. [Chunkers](#73-chunkers)
        * 7.3.1. [Chunking strategies](#731-chunking-strategies)
        * 7.3.2. [Automatic and disabled chunking](#732-automatic-and-disabled-chunking)
    * 7.4. [Embeddings and vectors](#74-embeddings-and-vectors)
    * 7.5. [Vector store](#75-vector-store)
        * 7.5.1. [In-memory vector store](#751-in-memory-vector-store)
    * 7.6. [Metadata filters](#76-metadata-filters)
    * 7.7. [Retriever](#77-retriever)
    * 7.8. [Knowledge base](#78-knowledge-base)
    * 7.9. [Augmenting user queries](#79-augmenting-user-queries)
8. [Chat service](#8-chat-service)
    * 8.1. [Listener](#81-listener)
    * 8.2. [Chat service](#82-chat-service)
    * 8.3. [Chat messages](#83-chat-messages)
    * 8.4. [Approval error responses](#84-approval-error-responses)
    * 8.5. [Chat client](#85-chat-client)
9. [Observability](#9-observability)
    * 9.1. [Spans](#91-spans)
    * 9.2. [Span factory functions](#92-span-factory-functions)
    * 9.3. [Current span](#93-current-span)
10. [Errors](#10-errors)
    * 10.1. [Error hierarchy](#101-error-hierarchy)
    * 10.2. [Error types](#102-error-types)

## 1. Overview
Ballerina language provides first-class support for writing network-oriented programs. The AI standard library builds on these language constructs and provides a vendor-neutral programming model for integrating LLMs into Ballerina applications.

The library defines abstract types such as `ai:ModelProvider`, `ai:EmbeddingProvider`, `ai:VectorStore`, and `ai:Memory`. Vendor-specific implementations of these types are provided by separate connector packages (for example, `ballerinax/ai.openai`, `ballerinax/ai.anthropic`, and vector store connectors), so that application code written against the abstractions can switch providers without changes. The library also ships default implementations backed by the WSO2 AI service, and in-memory implementations suitable for development and testing.

On top of these abstractions, the library provides the following high-level components.

* **Direct LLM calls** — chat completion and structured generation from natural-language prompts written as Ballerina raw templates, with the result bound to a Ballerina type.
* **Agents** — `ai:Agent` runs a reasoning loop that lets an LLM call Ballerina functions, MCP servers, and HTTP services as tools, keeps per-session conversation memory, and supports human-in-the-loop approval of tool calls.
* **Retrieval-augmented generation** — documents, data loaders, chunkers, embeddings, vector stores, retrievers, and knowledge bases.
* **Chat services** — `ai:Listener` and `ai:ChatService` expose an agent over HTTP, and `ai:ChatClient` consumes such a service.
* **Observability** — the `ai.observe` module emits tracing spans for model, agent, tool, and knowledge base operations.

A compiler plugin complements the runtime by generating JSON schemas for tools at compile time and validating their usage. Each component is discussed in detail in the coming sections.

## 2. Model providers

### 2.1. ModelProvider

The `ai:ModelProvider` type is the abstraction over a large language model (LLM). Every component of the library
that talks to an LLM (agents, model-assisted memory, and so on) depends only on this type, so any LLM can be plugged
in by providing an implementation. Provider-specific implementations are distributed as separate connector packages
such as `ballerinax/ai.openai` and `ballerinax/ai.anthropic`. The library itself ships one implementation, the
`ai:Wso2ModelProvider` (see [Section 2.5](#25-default-wso2-model-provider)).

A model provider is a distinct isolated client object that exposes two remote methods:

* `chat`: a multi-turn conversational call that supports function calling (tools).
* `generate`: a single-turn call that maps the LLM response to a Ballerina type (structured output).

```ballerina
public type ModelProvider distinct isolated client object {
    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [], string? stop = ())
        returns ChatAssistantMessage|Error;
    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error;
};
```

A custom provider is implemented by including the type in a client class. Because `generate` is a dependently-typed
function, Ballerina requires it to be implemented as an external function; a provider binds it to a native
implementation, as `ai:Wso2ModelProvider` does.

```ballerina
import ballerina/ai;
import ballerina/jballerina.java;

public isolated client class MyModelProvider {
    *ai:ModelProvider;

    isolated remote function chat(ai:ChatMessage[]|ai:ChatUserMessage messages,
            ai:ChatCompletionFunctions[] tools = [], string? stop = ()) returns ai:ChatAssistantMessage|ai:Error {
        // Call the LLM and map its response to an assistant message.
        return {role: ai:ASSISTANT, content: "..."};
    }

    isolated remote function generate(ai:Prompt prompt, typedesc<anydata> td = <>) returns td|ai:Error = @java:Method {
        'class: "org.example.provider.Generator"
    } external;
}
```

### 2.2. Chat messages

A conversation is represented as an array of chat messages. Each message is a closed record whose `role` field
discriminates the message kind.

```ballerina
public enum ROLE {
    SYSTEM = "system",
    USER = "user",
    ASSISTANT = "assistant",
    FUNCTION = "function"
}

public type ChatUserMessage record {|
    USER role;
    string|Prompt content;
    string name?;
|};

public type ChatSystemMessage record {|
    SYSTEM role;
    string|Prompt content;
    string name?;
|};

public type ChatAssistantMessage record {|
    ASSISTANT role;
    string? content = ();
    string name?;
    FunctionCall[]? toolCalls = ();
|};

public type ChatFunctionMessage record {|
    FUNCTION role;
    string? content = ();
    string name;
    string id?;
|};

public type ChatMessage ChatUserMessage|ChatSystemMessage|ChatAssistantMessage|ChatFunctionMessage;

public type ChatInteractiveMessage ChatUserMessage|ChatAssistantMessage|ChatFunctionMessage;
```

* `ChatUserMessage` and `ChatSystemMessage` carry either a plain `string` or an `ai:Prompt` template (see
  [Section 2.4](#24-generate-and-prompt-templates)) as the content.
* `ChatAssistantMessage` is the LLM response. When the LLM decides to call tools, `toolCalls` holds one
  `FunctionCall` per requested invocation and `content` may be `()`.
* `ChatFunctionMessage` carries the result of a tool invocation back to the LLM. `name` is the tool name and `id`
  correlates the result with the `FunctionCall.id` it answers.
* `ChatInteractiveMessage` is `ChatMessage` without the system message, i.e. the messages exchanged during a
  conversation.

Tools offered to the LLM and the calls requested by the LLM are described by the following records.

```ballerina
public type ChatCompletionFunctions record {|
    string name;
    string description;
    map<json> parameters?;
|};

public type FunctionCall record {|
    string name;
    map<json>? arguments = {};
    string id?;
|};
```

`ChatCompletionFunctions.parameters` is the JSON schema of the tool input.

### 2.3. Chat

The `chat` remote method sends a conversation to the LLM and returns the next assistant message.

* When a single `ChatUserMessage` is passed, the call is stateless: the LLM has no prior context.
* When a `ChatMessage[]` is passed, the LLM considers the whole conversation history. The caller is responsible for
  appending the returned `ChatAssistantMessage` (and any subsequent messages) to the history.
* `tools` lists the functions the LLM may request. When the LLM requests tool calls, they are returned in
  `ChatAssistantMessage.toolCalls`; the method does not execute them.
* `stop` is an optional stop sequence.

A failure to reach the LLM is reported as `ai:LlmConnectionError` (see [Section 10](#10-errors)). For the
`ai:Wso2ModelProvider`, a response without any choices is reported as `ai:LlmInvalidResponseError`, and tool-call
arguments that cannot be parsed as JSON are reported as `ai:LlmError`.

```ballerina
public function main(string subject) returns error? {
    ai:ChatMessage[] messages = [{role: ai:USER, content: `Tell me a joke about ${subject}!`}];

    ai:ChatAssistantMessage joke = check model->chat(messages);
    messages.push(joke);

    messages.push({role: ai:USER, content: "Can you explain it?"});
    ai:ChatAssistantMessage explanation = check model->chat(messages);
    io:println(explanation?.content);
}
```

### 2.4. Generate and prompt templates

#### 2.4.1. Prompt

The `ai:Prompt` type is a raw template type. A backtick template assigned to a context that expects `ai:Prompt`
creates a value of this type. The fixed parts of the template are kept in `strings` and the interpolated values in
`insertions`. Insertions may be `anydata` values, documents, or chunks (see [Section 7](#7-retrieval-augmented-generation)).

```ballerina
public type Prompt object {
    *object:RawTemplate;
    public string[] & readonly strings;
    public (anydata|Document|Document[]|Chunk|Chunk[])[] insertions;
};
```

An `anydata` insertion is rendered as text. A `Document`/`Chunk` insertion lets a provider send non-text content
(e.g. images) to the LLM. The set of document kinds a provider accepts is provider-specific. In `generate`, the
`ai:Wso2ModelProvider` accepts `ai:TextDocument`, `ai:TextChunk` and `ai:ImageDocument` and returns an error for any
other document kind. In `chat`, a `Prompt` used as message content is flattened to a single trimmed string, and every
insertion, including documents and chunks, is rendered as text.

#### 2.4.2. Structured output

The `generate` remote method sends a single prompt to the LLM and binds the response to the type described by `td`.
The expected type is inferred from the assignment context when `td` is not given explicitly, and it MUST be a
subtype of `json`. This is not checked at compile time; with the `ai:Wso2ModelProvider`, an expected type that is not
a subtype of `json` (e.g. one containing `xml` or `table`) causes a panic rather than an error.

```ballerina
type JokeResponse record {|
    string setup;
    string punchline;
|};

public function main(string subject) returns error? {
    string joke = check model->generate(`Tell me a joke about ${subject}!`);

    JokeResponse jokeResponse = check model->generate(`Tell me a joke about ${subject}!`);
    io:println(jokeResponse.setup, " ", jokeResponse.punchline);
}
```

A provider derives a JSON schema from the expected type and instructs the LLM to respond in that shape. The schema is
resolved in the following order:

1. The schema given by the `@ai:JsonSchema` annotation on the type, if present.
2. Otherwise, the schema generated for the type by the compiler plugin at compile time, if one was generated.
3. Otherwise, a schema generated from the type at runtime.

The `@ai:JsonSchema` annotation lets users override the generated schema for a type.

```ballerina
public annotation map<json> JsonSchema on type;
```

```ballerina
@ai:JsonSchema {
    "type": "object",
    "properties": {
        "rating": {"type": "integer", "minimum": 1, "maximum": 5}
    },
    "required": ["rating"]
}
type Review record {|
    int rating;
|};
```

The `ai:Wso2ModelProvider` implements structured output by exposing the schema as a single `getResults` tool and
forcing the LLM to call it. When the expected type is not a JSON object, the schema is wrapped in an object under a
`result` property and the value of that property is bound to the expected type. If the response cannot be bound to
the expected type, `generate` returns an `ai:LlmInvalidGenerationError`. Other failures are returned as a plain
`ai:Error` and are not retried: a failure to reach the LLM (`LLM call failed`), and a response that has no
`getResults` tool call or whose arguments are not valid JSON (`No relevant response from the LLM`).

#### 2.4.3. Generator configuration

Providers can be configured to retry when the LLM response cannot be bound to the expected type. On each retry the
binding error is sent back to the LLM so it can correct the response.

```ballerina
public type GeneratorConfig record {|
    RetryConfig retryConfig?;
|};

public type RetryConfig record {|
    int count = 0;
    decimal interval?;
|};
```

* `count` is the number of retries. The default `0` disables retrying. A negative value is an error.
* `interval` is the delay in seconds between retries. It defaults to `0` and MUST NOT be negative.

```ballerina
final ai:Wso2ModelProvider model = check new (serviceUrl, accessToken,
    generatorConfig = {retryConfig: {count: 2, interval: 1}});
```

### 2.5. Default WSO2 model provider

The `ai:Wso2ModelProvider` is a model provider backed by the WSO2 AI service. It calls the service's
`/chat/completions` endpoint using the given access token.

```ballerina
public isolated distinct client class Wso2ModelProvider {
    *ModelProvider;

    public isolated function init(string serviceUrl, string accessToken,
            decimal temperature = 0.7,
            readonly & GeneratorConfig generatorConfig = {},
            *ConnectionConfig connectionConfig) returns Error?;

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [], string? stop = ())
        returns ChatAssistantMessage|Error;

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error;
}
```

`temperature` defaults to `0.7`. `connectionConfig` configures the underlying HTTP client.

```ballerina
public type ConnectionConfig record {|
    http:HttpVersion httpVersion = http:HTTP_2_0;
    http:ClientHttp1Settings http1Settings = {};
    http:ClientHttp2Settings http2Settings = {};
    decimal timeout = 60;
    string forwarded = "disable";
    http:PoolConfiguration poolConfig?;
    http:CacheConfig cache = {};
    http:Compression compression = http:COMPRESSION_AUTO;
    http:CircuitBreakerConfig circuitBreaker?;
    http:RetryConfig retryConfig?;
    http:ResponseLimitConfigs responseLimits = {};
    http:ClientSecureSocket secureSocket?;
    http:ProxyConfig proxy?;
    boolean validation = true;
|};
```

The library declares a module-level configurable of the following type. When it is set, the default WSO2 model and
embedding providers (see [Section 3.2](#32-default-wso2-embedding-provider)) are created during module
initialization.

```ballerina
public type Wso2ProviderConfig record {|
    string serviceUrl;
    string accessToken;
|};

configurable Wso2ProviderConfig? wso2ProviderConfig = ();
```

```toml
[ballerina.ai.wso2ProviderConfig]
serviceUrl = "<service-url>"
accessToken = "<access-token>"
```

The `getDefaultModelProvider` function returns the default model provider. It returns an `ai:Error` when the
`wso2ProviderConfig` configurable is not set.

```ballerina
public isolated function getDefaultModelProvider() returns Wso2ModelProvider|Error;
```

```ballerina
final ai:ModelProvider model = check ai:getDefaultModelProvider();
```

## 3. Embedding providers

### 3.1. EmbeddingProvider

The `ai:EmbeddingProvider` type is the abstraction over an embedding model. It converts chunks into vector
embeddings (see [Section 7.4](#74-embeddings-and-vectors)) and is used by retrievers and knowledge bases.
Like model providers, concrete implementations are distributed as connector packages.

```ballerina
public type EmbeddingProvider distinct isolated client object {
    isolated remote function embed(Chunk chunk) returns Embedding|Error;
    isolated remote function batchEmbed(Chunk[] chunks) returns Embedding[]|Error;
};
```

* `embed` returns the embedding of a single chunk.
* `batchEmbed` returns the embeddings of the given chunks, in the same order.

```ballerina
ai:Embedding embedding = check embeddingProvider->embed({'type: "text-chunk", content: "Ballerina is a programming language"});
```

### 3.2. Default WSO2 embedding provider

The `ai:Wso2EmbeddingProvider` is an embedding provider backed by the WSO2 AI service. It only accepts
`ai:TextChunk` and `ai:TextDocument` values and returns an `ai:Error` for any other chunk type.

```ballerina
public distinct isolated client class Wso2EmbeddingProvider {
    *EmbeddingProvider;

    public isolated function init(string serviceUrl, string accessToken, *ConnectionConfig connectionConfig) returns Error?;

    isolated remote function embed(Chunk chunk) returns Embedding|Error;

    isolated remote function batchEmbed(Chunk[] chunks) returns Embedding[]|Error;
}
```

When the `wso2ProviderConfig` configurable is set (see [Section 2.5](#25-default-wso2-model-provider)), a default
instance is created and returned by `getDefaultEmbeddingProvider`. The function returns an `ai:Error` when the
configurable is not set.

```ballerina
public isolated function getDefaultEmbeddingProvider() returns Wso2EmbeddingProvider|Error;
```

## 4. Tools

A tool is a function that an agent can ask the LLM to invoke. Internally the agent understands a single tool
representation, `ai:ToolConfig` (see [Section 4.2](#42-tool-configuration)). Function tools and toolkits are
converted to this representation when the agent is created.

### 4.1. Function tools

A function tool is an isolated function, or an isolated method of an object, annotated with `@ai:AgentTool`.

```ballerina
public type FunctionTool isolated function;

public annotation ToolAnnotationConfig AgentTool on function, object function;

public type ToolAnnotationConfig record {|
    string name?;
    string description?;
    ObjectInputSchema? parameters?;
    AgentIdAuthConfig|Scopes auth?;
    RequiresApproval requiresApproval = false;
|};
```

* `name`: the tool name. Defaults to the function name.
* `description`: what the tool does, used by the LLM to decide when to call it. Defaults to the description in the
  function's documentation comment, or the function name when there is none.
* `parameters`: the JSON schema of the tool input. When omitted, it is generated from the function's parameters,
  including their documentation comments (see [Section 4.1.1](#411-schema-generation-and-constraints)).
* `auth`: the authorization the tool requires (see [Section 4.4](#44-tool-authorization)).
* `requiresApproval`: whether the agent must obtain human approval before invoking the tool (see
  [Section 5.5](#55-human-in-the-loop-approval)).

```ballerina
public type RequiresApproval boolean|isolated function;
```

The default values of `name`, `description` and `parameters` are filled in at compile time by the compiler plugin.

```ballerina
# Retrieves the current weather for a given city.
# + city - Name of the city
# + return - The weather report
@ai:AgentTool
isolated function getWeather(string city) returns string|error {
    // ...
}
```

#### 4.1.1. Schema generation and constraints

The compiler plugin validates every function annotated with `@ai:AgentTool` and reports a compilation error when a
constraint is violated.

* Every parameter MUST be a subtype of `anydata`.
* A parameter type MUST NOT be or contain `xml`, directly or within its fields.
* The return type MUST be a subtype of `anydata|http:Response|stream<anydata, error?>|error`.
* A parameter of type `ai:Context` is allowed only as the first parameter. It is not part of the input
  schema; the agent passes the `ai:Context` given to `run` (see [Section 4.5](#45-context)).
* When the input schema cannot be generated from the parameter types, the schema MUST be given through the
  `parameters` field of the annotation.
* When `requiresApproval` is a function, it MUST have the same parameters (names and types, excluding a leading
  `ai:Context` of the tool) as the tool and return `boolean`.

The input schema is an object schema with one property per parameter. Parameters without a default value are listed
as `required`, and parameter documentation becomes the property `description`. When the tool is invoked, the
arguments generated by the LLM are bound to the parameters by name; parameters with default values that the LLM
omitted take their default values.

Input schemas are described by the following types.

```ballerina
public enum InputType {
    STRING = "string",
    INTEGER = "integer",
    FLOAT = "float",
    BOOLEAN = "boolean",
    NUMBER = "number",
    OBJECT = "object",
    ARRAY = "array",
    NULL = "null"
}

public type PrimitiveType int|string|boolean|float|decimal;

public type ConstantValueSchema record {|
    json 'const;
|};

public type InternalValueSchema record {|
    *ConstantValueSchema;
|};

public type BaseInputSchema record {|
    string description?;
    json default?;
    boolean nullable?;
|};

public type BaseInputTypeSchema record {|
    *BaseInputSchema;
    InputType 'type;
|};

public type PrimitiveInputSchema record {|
    *BaseInputTypeSchema;
    STRING|INTEGER|NUMBER|BOOLEAN|NULL 'type;
    string format?;
    string pattern?;
    (PrimitiveType?)[] 'enum?;
    PrimitiveType default?;
|};

public type AnyOfInputSchema record {|
    *BaseInputSchema;
    JsonSubSchema[] anyOf;
|};

public type AllOfInputSchema record {|
    *BaseInputSchema;
    JsonSubSchema[] allOf;
|};

public type OneOfInputSchema record {|
    JsonSubSchema[] oneOf;
    boolean nullable?;
    string description?;
|};

public type NotInputSchema record {|
    *BaseInputSchema;
    JsonSubSchema not;
|};

public type ArrayInputSchema record {|
    *BaseInputTypeSchema;
    ARRAY 'type = ARRAY;
    JsonSubSchema items;
    json[] default?;
|};

public type ObjectInputSchema record {|
    *BaseInputTypeSchema;
    OBJECT 'type = OBJECT;
    string[] required?;
    map<JsonSubSchema> properties?;
|};

public type JsonInputSchema ObjectInputSchema|ArrayInputSchema|AnyOfInputSchema|OneOfInputSchema|AllOfInputSchema|NotInputSchema;

public type JsonSubSchema JsonInputSchema|PrimitiveInputSchema|ConstantValueSchema;
```

A property described by a `ConstantValueSchema` is not exposed to the LLM. It is removed from the schema sent to the
LLM and its `const` value is supplied to the tool on every invocation. Likewise, `default` values in the schema are
used for inputs the LLM omits.

### 4.2. Tool configuration

`ai:ToolConfig` is the only tool representation directly understood by the agent. It can be passed to an agent
as-is, and it is what toolkits produce.

```ballerina
public type ToolConfig record {|
    string name;
    string description;
    map<json>? parameters = ();
    FunctionTool caller;
    AgentIdAuthConfig|Scopes auth?;
    RequiresApproval requiresApproval = false;
|};
```

* `parameters` is the JSON schema of the tool input, or `()` when the tool takes no input.
* `caller` is the function invoked with the arguments generated by the LLM.

When tools are registered with an agent:

* Tool names MUST be unique across all tools and toolkits registered with the agent. A duplicate name results in an
  `ai:Error`.
* A name matching `final.?answer` (case-insensitive) is reserved and results in an `ai:Error`.
* A name that does not match `^[a-zA-Z0-9_-]{1,64}$` is sanitized by truncating it to 64 characters and replacing
  every other character with `_`, and a warning is logged.

The `getToolConfigs` function converts function tools annotated with `@ai:AgentTool` to `ai:ToolConfig` values. A
function that cannot be converted (e.g. one without the annotation) is skipped and a warning is logged.

```ballerina
public isolated function getToolConfigs(FunctionTool[] tools) returns ToolConfig[];
```

```ballerina
ai:ToolConfig[] tools = ai:getToolConfigs([getWeather, getForecast]);
```

### 4.3. Toolkits

A toolkit groups several tools and produces them as `ai:ToolConfig` values. Toolkits are passed to an agent alongside
function tools and tool configs.

#### 4.3.1. BaseToolKit

User-defined toolkits are implemented by including `ai:BaseToolKit`. The agent calls `getTools` when it is created.

```ballerina
public type BaseToolKit distinct object {
    public isolated function getTools() returns ToolConfig[];
};
```

```ballerina
isolated class CalculatorToolKit {
    *ai:BaseToolKit;

    public isolated function getTools() returns ai:ToolConfig[] => ai:getToolConfigs([self.add, self.subtract]);

    @ai:AgentTool
    isolated function add(int a, int b) returns int => a + b;

    @ai:AgentTool
    isolated function subtract(int a, int b) returns int => a - b;
}
```

#### 4.3.2. MCP toolkit

The `ai:McpToolKit` exposes the tools of a remote [Model Context Protocol](https://modelcontextprotocol.io) (MCP)
server over the streamable HTTP transport. During initialization it connects to the server, performs the MCP
`initialize` handshake, and lists the server's tools. When `permittedTools` is given, only the tools with those names
are exposed; otherwise all tools are exposed. Each tool's name, description and input schema are taken from the
server. Invoking a tool sends an MCP `tools/call` request to the server.

```ballerina
public type McpBaseToolKit distinct isolated object {
    *BaseToolKit;
};

public isolated class McpToolKit {
    *McpBaseToolKit;

    public isolated function init(string serverUrl, string[]? permittedTools = (),
            mcp:Implementation info = {name: "MCP Client", version: "1.0.0"},
            *StreamableHttpClientTransportConfig config) returns Error?;

    public isolated function callTool(mcp:CallToolParams params) returns mcp:CallToolResult|error;

    public isolated function getTools() returns ToolConfig[];
}
```

```ballerina
public type StreamableHttpClientTransportConfig record {|
    http:HttpVersion httpVersion = http:HTTP_2_0;
    http:ClientHttp1Settings http1Settings = {};
    http:ClientHttp2Settings http2Settings = {};
    decimal timeout = 30;
    string forwarded = "disable";
    http:FollowRedirects? followRedirects = ();
    http:PoolConfiguration? poolConfig = ();
    http:CacheConfig cache = {};
    http:Compression compression = http:COMPRESSION_AUTO;
    http:CircuitBreakerConfig? circuitBreaker = ();
    http:RetryConfig? retryConfig = ();
    http:CookieConfig? cookieConfig = ();
    http:ClientAuthConfig|AgentIdAuthConfig? auth = ();
    http:ResponseLimitConfigs responseLimits = {};
    http:ProxyConfig? proxy = ();
    boolean validation = true;
    http:ClientSocketConfig socketConfig = {};
    boolean laxDataBinding = false;
    http:ClientSecureSocket? secureSocket = ();
    string sessionId?;
|};
```

An `http:ClientAuthConfig` given as `auth` is used to authenticate with the MCP server.

```ballerina
final ai:McpToolKit githubTools = check new ("https://api.githubcopilot.com/mcp/",
    permittedTools = ["list_issues", "get_issue"]);
```

Custom MCP toolkits that need per-tool configuration (e.g. approval or scopes) are implemented by including
`ai:McpBaseToolKit` and building the tools with `getPermittedMcpToolConfigs`. Each permitted tool is mapped to a
dispatcher function annotated with `@ai:AgentTool` that has the signature
`isolated function (mcp:CallToolParams params) returns mcp:CallToolResult|error`. `permittedTools` is either a map
from MCP tool name to its dispatcher, which exposes only the tools in the map, or a single dispatcher, which exposes
all tools. The `requiresApproval` and `auth` scopes of each dispatcher's annotation apply to the tool. When invoking
an MCP tool, the agent calls the dispatcher with an `mcp:CallToolParams` value carrying the tool name and the
arguments generated by the LLM.

```ballerina
public isolated function getPermittedMcpToolConfigs(mcp:StreamableHttpClient mcpClient, mcp:Implementation info,
        map<FunctionTool>|FunctionTool permittedTools, AgentIdAuthConfig? auth = ()) returns ToolConfig[]|Error;
```

```ballerina
isolated class GithubToolKit {
    *ai:McpBaseToolKit;
    private final mcp:StreamableHttpClient mcpClient;
    private final readonly & ai:ToolConfig[] tools;

    public isolated function init(string serverUrl, mcp:Implementation info = {name: "Github", version: "1.0.0"})
            returns ai:Error? {
        final map<ai:FunctionTool> permittedTools = {"list_issues": self.listIssues};
        do {
            self.mcpClient = check new (serverUrl);
            self.tools = check ai:getPermittedMcpToolConfigs(self.mcpClient, info, permittedTools).cloneReadOnly();
        } on fail error e {
            return error ai:Error("Failed to initialize the toolkit", e);
        }
    }

    public isolated function getTools() returns ai:ToolConfig[] => self.tools;

    @ai:AgentTool {requiresApproval: true}
    isolated function listIssues(mcp:CallToolParams params) returns mcp:CallToolResult|error {
        return self.mcpClient->callTool(params);
    }
}
```

#### 4.3.3. HTTP service toolkit

The `ai:HttpServiceToolKit` exposes the resources of a single HTTP API as tools. Each `ai:HttpTool` describes one
resource; invoking the tool sends a request with the corresponding HTTP method to the resource and returns an
`ai:HttpOutput`.

```ballerina
public isolated class HttpServiceToolKit {
    *BaseToolKit;

    public isolated function init(string serviceUrl, HttpTool[] httpTools, http:ClientConfiguration clientConfig = {},
            map<string|string[]> headers = {}) returns Error?;

    public isolated function getTools() returns ToolConfig[];
}
```

```ballerina
public enum HttpMethod {
    GET, POST, DELETE, PUT, PATCH, HEAD, OPTIONS
}

public type HttpTool record {|
    string name;
    string description;
    HttpMethod method;
    string path;
    map<ParameterSchema> parameters?;
    RequestBodySchema requestBody?;
|};

public type ParameterSchema record {|
    PATH|QUERY location;
    string description?;
    boolean required?;
    EncodingStyle style?;
    boolean explode?;
    boolean nullable?;
    boolean allowEmptyValue?;
    string mediaType?;
    JsonSubSchema schema;
|};

public type RequestBodySchema record {|
    string description?;
    string mediaType?;
    JsonSubSchema schema;
|};

public type HttpOutput record {|
    int code;
    string path;
    record {|
        string contentType?;
        int contentLength?;
    |} headers;
    json|xml body?;
|};
```

* Path parameters, and query parameters with `required` set to `true`, are required inputs of the tool.
* `headers` are added to every request sent by the toolkit.

```ballerina
final ai:HttpServiceToolKit petStore = check new ("http://localhost:9090/petstore", [
    {
        name: "getPet",
        description: "Retrieves a pet by its ID",
        method: ai:GET,
        path: "/pets/{petId}",
        parameters: {
            petId: {location: ai:PATH, schema: {'type: ai:INTEGER}}
        }
    }
]);
```

##### 4.3.3.1. Tools from OpenAPI specifications

HTTP tools can be extracted from an OpenAPI 3.0.x or 3.1.x specification, given either as a file (`.json`, `.yaml` or
`.yml`) or as a JSON value. Each operation becomes an `ai:HttpTool`, and the server URL of the specification, if any,
is returned as `serviceUrl`.

```ballerina
public type HttpApiSpecification record {|
    string serviceUrl?;
    HttpTool[] tools;
|};

public type AdditionInfoFlags record {|
    boolean extractDescription = false;
    boolean extractDefault = false;
|};

public isolated function extractToolsFromOpenApiSpecFile(string filePath, *AdditionInfoFlags additionInfoFlags)
    returns HttpApiSpecification & readonly|Error;

public isolated function extractToolsFromOpenApiJsonSpec(map<json> openApiSpec, *AdditionInfoFlags additionInfoFlags)
    returns HttpApiSpecification & readonly|Error;

public isolated function parseOpenApiSpec(map<json> openApiSpec)
    returns OpenApiSpec|UnsupportedOpenApiVersion|OpenApiParsingError;
```

* `extractDescription` includes the descriptions of parameters and schema attributes in the tool schemas.
* `extractDefault` includes the default values of parameters and schema attributes in the tool schemas.
* A specification of another version results in an `ai:UnsupportedOpenApiVersion` error, and an invalid one in an
  `ai:OpenApiParsingError` (see [Section 10](#10-errors)).

```ballerina
ai:HttpApiSpecification spec = check ai:extractToolsFromOpenApiSpecFile("petstore.yaml");
final ai:HttpServiceToolKit petStore = check new (spec.serviceUrl ?: "http://localhost:9090", spec.tools);
```

### 4.4. Tool authorization

A tool can declare the authorization it requires through the `auth` field of `@ai:AgentTool` or `ai:ToolConfig`.
Tool authorization relies on the agent having an identity, configured with the `credential` field of the agent
configuration (see [Section 5.6](#56-agent-identity)).

```ballerina
public type AgentIdAuthConfig record {|
    string baseAuthUrl;
    string clientId;
    string clientSecret?;
    string redirectUri;
    string|string[] scopes?;
    boolean isPkceEnabled = false;
    http:ClientSecureSocket? secureSocket = ();
|};

public type Scopes record {|
    string|string[] scopes?;
|};
```

* `ai:AgentIdAuthConfig` configures the authorization server from which the agent obtains an access token on behalf
  of its identity, and the scopes the token must carry. It is used for function tools.
* `ai:Scopes` lists only the scopes. It is used for MCP dispatcher functions, whose authorization server is given by
  the `auth` argument of `getPermittedMcpToolConfigs`.

When the `auth` field is given as an inline mapping constructor, the compiler plugin checks that the expected kind is
used. A tool is treated as an MCP dispatcher when it has an `mcp:CallToolParams` parameter or its return type is a
union that includes `mcp:CallToolResult`. Such a tool must use `ai:Scopes`, and any other tool must use
`ai:AgentIdAuthConfig`. The two are told apart by field count: a mapping with exactly one field is treated as
`ai:Scopes`. An `auth` value given as a variable reference is not checked.

Before invoking a tool that declares `ai:AgentIdAuthConfig` auth, an agent with a credential:

1. Reuses the cached access token for the tool, or obtains a new one from the authorization server when there is no
   cached token or it has expired. A failure to obtain a token results in an `ai:TokenAcquisitionError`, and a token
   that cannot be decoded as a JWT in an `ai:TokenValidationError`. A newly obtained token that has already expired is
   neither cached nor made available to the tool; if the tool requires scopes, this results in an
   `ai:InsufficientScopeError` in the next step.
2. Verifies that the token carries every required scope. A missing scope results in an `ai:InsufficientScopeError`.
3. Makes the token available to the tool through `ai:Context.getAccessToken` (see [Section 4.5](#45-context)).

When a tool declares scopes but the agent has no credential, or the tool's auth is not an `ai:AgentIdAuthConfig`,
the invocation fails with an `ai:TokenAcquisitionError`.

```ballerina
@ai:AgentTool {
    auth: {
        baseAuthUrl: "https://idp.example.com",
        clientId: "<client-id>",
        redirectUri: "https://localhost:9090/callback",
        scopes: ["orders:read"]
    }
}
isolated function listOrders(ai:Context ctx) returns json|error {
    string token = check ctx.getAccessToken("listOrders");
    // Call the orders API with the token.
}
```

### 4.5. Context

The `ai:Context` object carries additional data from the caller of an agent to its tools. A context is passed to
`run` of the agent (see [Section 5.2](#52-running-an-agent)), and the agent passes it to every tool whose first parameter is of
type `ai:Context`. When no context is passed, a new empty context is used.

```ballerina
public type Cloneable (any & readonly)|xml|Cloneable[]|map<Cloneable>|table<map<Cloneable>>;

public type ContextEntry Cloneable|isolated object {};

public isolated class Context {
    public isolated function set(string key, ContextEntry value);
    public isolated function get(string key) returns ContextEntry;
    public isolated function hasKey(string key) returns boolean;
    public isolated function keys() returns string[];
    public isolated function getAccessToken(string toolName) returns string|error;
    public isolated function getWithType(string key, typedesc<ContextEntry> targetType = <>) returns targetType|Error;
    public isolated function remove(string key);
}
```

* `set` adds or replaces an entry. `Cloneable` values are cloned when stored and when retrieved, so callers and
  tools never share mutable state through the context; isolated objects are stored by reference.
* `get` and `remove` panic when the key does not exist. `hasKey` checks for a key without panicking.
* `getWithType` returns the entry converted to the expected type, or an `ai:Error` when the entry is missing or of a
  different type.
* `getAccessToken` returns the access token obtained for the given tool (see [Section 4.4](#44-tool-authorization)),
  or an error when there is none.

```ballerina
@ai:AgentTool
isolated function getOrders(ai:Context ctx, string status) returns json|error {
    string userId = check ctx.getWithType("userId");
    // ...
}

public function main() returns error? {
    ai:Context ctx = new;
    ctx.set("userId", "u-123");
    string answer = check agent.run("List my pending orders", context = ctx);
}
```

## 5. Agents

An agent combines a model provider, a set of tools, and a memory to complete a task through a series of
reasoning-action cycles. In each cycle the agent asks the model to either select tools to call or produce the
final answer. It executes the selected tools and feeds their results back to the model in the next cycle, until
the model produces an answer or the iteration limit is reached.

The `ai:Agent` class is the built-in agent implementation. Its behavior is configured through
`ai:AgentConfiguration` at construction time and it is invoked through the `run` method.

### 5.1. Agent configuration

```ballerina
public type SystemPrompt record {|
    string role;
    string instructions;
|};

public type AgentConfiguration record {|
    SystemPrompt systemPrompt;
    ModelProvider model;
    (BaseToolKit|ToolConfig|FunctionTool)[] tools = [];
    INFER_TOOL_COUNT|int maxIter = INFER_TOOL_COUNT;
    boolean verbose = false;
    Memory? memory?;
    ToolLoadingStrategy toolLoadingStrategy = NO_FILTER;
    boolean executeToolCallsInParallel = true;
    Credential credential?;
|};

public enum ToolLoadingStrategy {
    NO_FILTER,
    LLM_FILTER
}

public isolated distinct class Agent {
    *DependentlyTypedAgent;

    public isolated function init(*AgentConfiguration config) returns Error?;
    public isolated function run(anydata|Prompt|Resume query, string sessionId = DEFAULT_SESSION_ID,
            Context context = new, typedesc<Trace|anydata> td = <>) returns td|Error;
}
```

The configuration fields have the following semantics.

- `systemPrompt`: The `role` and `instructions` of the agent. They are rendered into the system message sent to
  the model as a `# Role` section followed by an `# Instructions` section.
- `model`: The `ai:ModelProvider` used for reasoning (see [Section 2](#2-model-providers)). The provider must
  support function calling, as tools are offered to the model through the `tools` parameter of `chat`.
- `tools`: The tools available to the agent. Each entry is a function annotated with `@ai:AgentTool`, an
  `ai:ToolConfig`, or a toolkit (see [Section 4](#4-tools)). Tools are registered in the agent's tool store at
  construction time; a tool that cannot be registered (e.g., a duplicate name) causes `init` to return an
  `ai:Error`.
- `maxIter`: The maximum number of reasoning-action cycles in a single run. One cycle is one call to the model
  plus the execution of every tool call returned in that response, so several tool calls proposed in one
  response count as a single iteration. When left as the default (`INFER_TOOL_COUNT`), the limit is
  `max(number of tools, 10)`.
- `verbose`: When `true`, the agent prints each iteration, the selected tool calls with their observations, and
  the final answer to the standard output.
- `memory`: The memory that stores the conversation history (see [Section 6](#6-memory)).
    - When the field is absent, the agent uses a new `ai:ShortTermMemory` backed by an in-memory store.
    - When the field is explicitly set to `()`, the agent is *stateless*. It still uses a private
      `ai:ShortTermMemory` during a run, but the history of the session is deleted at the end of every run, so no
      context is carried between runs.
- `toolLoadingStrategy`: Controls which tool schemas are sent to the model.
    - `NO_FILTER` (default): Every registered tool schema is sent on every model call.
    - `LLM_FILTER`: On the first model call of a turn, the agent first makes an additional model call that
      sends the conversation history, with the names and descriptions of the tools appended to the last user
      message, and asks the model to select the tools relevant to the query. Only the schemas of the selected tools are sent in the reasoning call that follows. If the
      selection call fails or its response cannot be interpreted, all tool schemas are sent. Later model calls
      in the same turn receive all tool schemas.
- `executeToolCallsInParallel`: When `true` (default) and a single model response contains more than one tool
  call, the calls are executed concurrently. Otherwise they are executed sequentially in the order the model
  returned them. The results are always fed back to the model in the original order.
- `credential`: The identity of the agent, used to obtain access tokens for secured tools (see
  [Section 5.6](#56-agent-identity)).

An `ai:Agent` declared at module level must be declared `final`; otherwise the compiler plugin reports a compilation
error. The check applies to a module-level variable declared with the type `ai:Agent` and an initializer; declarations
using `var`, an optional type such as `ai:Agent?`, or no initializer are not checked.

```ballerina
import ballerina/ai;

final ai:ModelProvider model = check ai:getDefaultModelProvider();

@ai:AgentTool
isolated function sum(decimal a, decimal b) returns decimal => a + b;

@ai:AgentTool
isolated function mult(decimal a, decimal b) returns decimal => a * b;

final ai:Agent mathTutorAgent = check new (
    systemPrompt = {
        role: "Math Tutor",
        instructions: "You are a school tutor assistant. Use the tools to perform calculations."
    },
    model = model,
    tools = [sum, mult],
    memory = check new ai:ShortTermMemory(check new ai:InMemoryShortTermMemoryStore(15))
);
```

### 5.2. Running an agent

The `run` method executes the agent for a query and binds the result to the type expected at the call site.

- `query`: The input of the turn. A `string` or any other `anydata` value is converted to a string, and an
  `ai:Prompt` is passed to the model as a prompt template. A `ai:Resume` value continues a run that paused for
  human approval instead of starting a new turn (see [Section 5.5](#55-human-in-the-loop-approval)). A `()`
  query results in an `ai:Error`.
- `sessionId`: Identifies the conversation in memory (see [Section 5.3](#53-sessions)).
- `context`: An `ai:Context` passed to tools that declare an `ai:Context` parameter (see
  [Section 4](#4-tools)).
- `td`: The expected return type, which is inferred from the call site.

The expected return type determines the form of the result.

| Expected type | Result on success | Result on failure |
|---|---|---|
| `string` | The final answer of the model. | `ai:Error` |
| `ai:Trace` | An `ai:Trace` whose `output` is the final answer as an `ai:ChatAssistantMessage`. | An `ai:Trace` whose `output` is the `ai:Error`. |
| Any other `anydata` type | The final answer bound to the type. | `ai:Error` |

When the expected type is neither `string` nor `ai:Trace`, the agent requests structured output. A JSON schema is
derived from the type, and an additional internal tool carrying that schema as its parameters is offered to the
model on each reasoning call. The system prompt instructs the model to deliver the final answer by calling that
tool. The arguments of that tool call become the final answer, which is then bound to the expected type.

- If the expected type is not a subtype of `json`, `run` returns an `ai:Error` before calling the model.
- If the model answers in plain text instead, the text is parsed as JSON (surrounding Markdown code fences are
  removed) and bound to the type.
- If binding fails, `run` returns an `ai:Error` that describes the binding failure.

```ballerina
type Weather record {|
    string city;
    decimal temperature;
|};

public function main() returns error? {
    // Plain text answer
    string answer = check mathTutorAgent.run("What is 8 + 9 multiplied by 10?", sessionId = "student-one");

    // Answer bound to a structured type
    Weather weather = check weatherAgent.run("What is the weather in Colombo?");

    // Full execution trace
    ai:Trace trace = check mathTutorAgent.run("What is 2 + 2?");
}
```

### 5.3. Sessions

Each run is associated with a session ID. The default session ID is `"sessionId"`.

At the start of a run, the agent loads the history of the session from memory.
- If loading fails, the run proceeds with an empty history.
- Any system message in the loaded history is dropped, and the agent's current system prompt is sent first. The
  history may therefore come from a memory that does not store a system message.
- The user message of the turn is then appended.

The messages produced during the run are written to memory in a single batch once the run ends, whether it
produced an answer or failed. Memory is not written when the run fails before the loop starts (for example, when
no schema can be derived for the expected type), or when a checkpoint for a pause cannot be persisted. The batch
contains:
- the system message
- the user message
- the tool call and tool result messages
- the final assistant message, if any

A run that pauses for human approval does not write to memory until it is resumed and completes. A failure to
update memory is logged and does not change the result of the run.

Calls to `run` with the same session ID must be made sequentially by the caller. Concurrent runs on the same
session are not supported. Runs on different session IDs may execute concurrently.

### 5.4. Execution loop

A run proceeds as follows.

1. Before each model call, the agent checks the iteration budget. If `maxIter` cycles have already been
   consumed, the loop stops without an answer.
2. The agent calls the model with the conversation history and the available tool schemas.
    - If the response contains tool calls, the agent executes them, then starts the next cycle. If structured
      output was requested and one of the calls is the structured-output tool, that call is treated as the
      final answer instead.
    - If the response contains no tool calls but has text content, that content is the final answer and the
      loop ends.
    - If the response contains neither, the iteration fails with an `ai:LlmInvalidGenerationError` and the loop
      ends.
    - If the model call itself returns an error (e.g., an `ai:LlmConnectionError`), the loop ends.
3. Each tool call is validated and executed.
    - The tool's result, or a description of its error, is returned to the model as an `ai:ChatFunctionMessage`.
      So an unknown tool name, invalid arguments, or a tool returning an error does not end the run, and the model
      can retry in the next cycle.
    - When the tool name or arguments fail validation before execution, the model receives only the fixed message
      `Tool extraction failed due to tool validation`, without details of the failure. When the tool fails during
      execution, the message states the kind of failure and includes the error in a `<detail>` element.
    - An `ai:UnauthorizedError` is the exception. It is raised when a token for a secured tool cannot be
      obtained or validated, and it ends the run. The final answer is then a fixed message stating that the
      request could not be completed due to an authorization issue.

When the run ends without a final answer, `run` returns an error:
- If the iteration budget was exhausted, `run` returns an `ai:MaxIterationExceededError`. Its `steps` detail
  field contains the steps executed in the run.
- If the run stopped because of an error, such as a failed model call, `run` returns an `ai:Error`.
    - The message has the form `Unable to obtain valid answer from the agent: <message of the underlying error>`.
    - The underlying error is set as its cause.
    - Its `steps` detail field contains the executed steps.
- If the only step of the run is an execution error caused by an `ai:MemoryError`, that `ai:MemoryError` is
  returned.
- In any other case, an `ai:Error` with the message `Unable to obtain valid answer from the agent` is returned.

The execution steps are described by the following types.

```ballerina
public type ExecutionResult record {|
    LlmToolResponse tool;
    anydata|error observation;
|};

public type ExecutionError record {|
    json llmResponse;
    LlmInvalidGenerationError|ToolExecutionError|MemoryError|UnauthorizedError 'error;
    string observation;
|};

public type LlmToolResponse record {|
    string name;
    map<json>? arguments = {};
    string id?;
|};
```

The error types are described in [Section 10](#10-errors).

### 5.5. Human-in-the-loop approval

A tool can require a human decision before the agent executes it. The requirement is declared on the tool
through the `requiresApproval` field of the `@ai:AgentTool` annotation or of `ai:ToolConfig` (see
[Section 4](#4-tools)).

```ballerina
public type RequiresApproval boolean|isolated function;

public type ApprovalRequest record {|
    string id;
    string sessionId;
    string toolName;
    string toolDescription;
    map<json> arguments;
    string toolCallId?;
    int batchIndex;
|};

public enum ApprovalOutcome {
    APPROVE,
    REJECT
}

public type HumanDecision record {|
    ApprovalOutcome outcome;
    string reason?;
|};

public type Resume readonly & record {|
    map<HumanDecision> decisions;
    ResumeTag tag = new;
|};

public distinct readonly class ResumeTag {
    *Tag;
}

public type Tag distinct object {
};
```

#### 5.5.1. Approval rules

The value of `requiresApproval` decides whether a call to the tool needs approval.

- `false` (the default): Calls to the tool never require approval.
- `true`: Every call to the tool requires approval.
- An `isolated` function: The decision is made for each call based on its arguments.
    - The function must have the same parameters as the tool and return `boolean`.
    - The arguments proposed by the model are bound to its parameters by name, in the same way they are bound to
      the tool.
    - Only the tool's `anydata` parameters are bound. A predicate that declares an `ai:Context` parameter
      cannot be bound.
    - The predicate fails safe: if it panics, returns a non-`boolean` value, or cannot be bound, the call requires
      approval.
    - On the `@ai:AgentTool` annotation, a predicate whose signature does not match the tool is rejected at
      compile time.

#### 5.5.2. Pausing a run

When a model response contains tool calls, the agent evaluates the approval rule of every call in the response
before executing any of them. A call whose tool name or arguments fail validation never requires approval; it
proceeds through the normal path and produces an error observation.

If at least one call requires approval, none of the calls in the response are executed and the run pauses.
- The agent creates an `ai:ApprovalRequest` for each call that requires approval, with a unique `id`.
  `batchIndex` is the position of the call within the model response.
- The paused state is persisted as an `ai:PendingApproval` checkpoint for the session.
- `run` returns an `ai:ApprovalRequiredError` whose `requests` detail field lists the requests. When the
  expected type is `ai:Trace`, an `ai:Trace` with that error as its `output` is returned instead.
- If the checkpoint cannot be persisted, the run does not pause. `run` returns an `ai:Error` stating that the
  run cannot be paused. When the expected type is `ai:Trace`, an `ai:Trace` with that error as its `output` is
  returned instead.

A pause is normal control flow, not a failure. The session's memory is not updated while a run is paused.

If `run` is called with a new query on a session that has a pending approval, no new turn is started. `run`
returns an `ai:ApprovalRequiredError` that lists the requests that are still pending. If the persisted checkpoint
is found to be corrupted, it is discarded with a warning and the new turn proceeds.

#### 5.5.3. Resuming a run

A paused run is continued by passing an `ai:Resume` value as the `query` of `run`, with the same session ID. The
`decisions` map is keyed by `ai:ApprovalRequest.id`.

- If the session has no pending approval, `run` returns an `ai:ApprovalNotFoundError`.
- If `decisions` contains an ID that is not pending for the session, `run` returns an
  `ai:UnknownApprovalIdError`. The pending approval is kept unchanged so that the call can be retried.
- If `decisions` covers only some of the pending requests, the supplied decisions are recorded and `run` returns
  a new `ai:ApprovalRequiredError` that lists only the undecided requests.
- Once every request has a decision, the whole batch is executed:
    - A rejected call is not executed. The model receives an observation stating that the human reviewer
      rejected the call, followed by `reason` when it is provided.
    - Approved calls, and calls in the batch that did not require approval, are executed as described in
      [Section 5.4](#54-execution-loop).
    - The run then continues with the next reasoning cycle.

The pending approval is claimed atomically when a resume starts. A concurrent duplicate resume for the same
session therefore fails with `ai:ApprovalNotFoundError` instead of executing the approved calls twice. The
iteration budget spans the whole logical run: iterations consumed before a pause count toward `maxIter` after
resuming. The `ai:Trace` of a resumed run covers every iteration of the logical run, and its `startTime` is the
start of the original run.

The expected return type is taken from the resuming call. When a structured type is expected, the same
structured-output tool is offered to the model again.

#### 5.5.4. Checkpoints

```ballerina
public type PendingApproval record {|
    string sessionId;
    string executionId;
    int iterationsUsed;
    ChatMessage[] history;
    int historyPrefixLength;
    Iteration[] iterations;
    FunctionCall[] toolCalls;
    time:Utc startTime;
    FunctionCall[] originalBatch = [];
    ApprovalRequest[] pendingRequests = [];
    HumanDecision?[] decisions = [];
|};
```

Where checkpoints are persisted depends on the agent's memory.
- If the memory is an `ai:ShortTermMemory`, checkpoints are persisted through it, in the same
  `ai:ShortTermMemoryStore` as the conversation history (see [Section 6.2](#62-short-term-memory)). A store with
  a durable backend therefore makes pauses survive a restart, or a resume on another replica.
- For any other memory implementation, checkpoints are kept in a private in-memory store that is not durable.
  The agent logs a warning at construction time if any of its tools can require approval.

```ballerina
import ballerina/ai;

@ai:AgentTool {
    requiresApproval: isolated function (string orderId, decimal amount) returns boolean => amount > 100d
}
isolated function issueRefund(string orderId, decimal amount) returns string => "refunded";

public function main() returns error? {
    string|ai:Error result = supportAgent.run("Refund order 42 for 250 USD", sessionId = "s1");
    if result is ai:ApprovalRequiredError {
        map<ai:HumanDecision> decisions = {};
        foreach ai:ApprovalRequest request in result.detail().requests {
            decisions[request.id] = {outcome: ai:APPROVE};
        }
        string answer = check supportAgent.run(<ai:Resume>{decisions: decisions.cloneReadOnly()}, sessionId = "s1");
    }
}
```

When an agent is exposed through an `ai:Listener`, approvals are exchanged through the `post decision` resource
(see [Section 8](#8-chat-service)).

### 5.6. Agent identity

```ballerina
public type Credential record {|
    string id;
    string secret;
|};
```

An agent can be given its own identity through the `credential` field of `ai:AgentConfiguration`. The agent
uses the credential to obtain access tokens on its own behalf for tools secured with an
`ai:AgentIdAuthConfig`. Tokens are cached by the agent and reused across calls. Tool authorization is described
in [Section 4](#4-tools). A failure to acquire or validate a token surfaces as an `ai:UnauthorizedError` and
ends the run, as described in [Section 5.4](#54-execution-loop).

### 5.7. Custom agents

Applications can define reusable agents as classes that compose an `ai:Agent` and expose a domain-specific
interface. The library defines two agent type abstractions for this purpose.

```ballerina
public type AgentType DependentlyTypedAgent|FixedTypedAgent;

public type DependentlyTypedAgent distinct isolated object {
    public isolated function run(anydata|Prompt|Resume query, string sessionId = DEFAULT_SESSION_ID,
            Context context = new, typedesc<Trace|anydata> td = <>) returns td|Error;
};

public type FixedTypedAgent distinct isolated object {
    public isolated function run(string|Prompt query, string sessionId = DEFAULT_SESSION_ID,
            Context context = new) returns anydata|Error;
    public isolated function trace(string|Prompt query, string sessionId = DEFAULT_SESSION_ID,
            Context context = new) returns Trace|Error;
};
```

- `ai:DependentlyTypedAgent`: The `run` result type is inferred from the call site, as with `ai:Agent`, which
  includes this type.
- `ai:FixedTypedAgent`: `run` returns a value of the implementation's own `anydata` type, and `trace` returns the
  full `ai:Trace` of the execution.

For each class that includes either type, the compiler plugin records an `ai:AgentMetadataConfig` value. It is
stored in the `agentMetadata` field of the class's `@display` annotation, so that consumers of a shared agent
definition can discover its composition without access to the implementation.
- If the class has a `@display` annotation, the field is merged into it.
- Otherwise, a `@display` annotation is added with the class name as its `label`.
- A `@display` annotation that already declares `agentMetadata` is left unchanged.

```ballerina
public enum ToolKind {
    FUNCTION_TOOL,
    MCP_TOOLKIT,
    TOOLKIT
}

public type ToolMetadata record {|
    string name;
    ToolKind kind;
    string label?;
    string icon?;
|};

public type ParameterInfo record {|
    string parameterName;
|};

public type AgentMetadataConfig record {|
    ToolMetadata[] tools = [];
    SystemPrompt systemPrompt?;
    ParameterInfo modelProvider?;
    ParameterInfo memory?;
|};
```

The metadata is derived from the `ai:Agent` constructed in the class's `init` method.
- `tools` lists the entries of the agent's `tools` argument that can be identified statically:
    - Function and method tools are listed by name, with their `@display` label and icon when present.
    - Inline `ai:ToolConfig` values are listed by their `name` field.
    - Toolkits are listed by variable name, or by type name when constructed inline. MCP toolkits have the kind
      `MCP_TOOLKIT` and other toolkits have the kind `TOOLKIT`.
    - Entries that cannot be resolved statically are omitted.
- `systemPrompt` is present only when both the role and the instructions are statically resolvable.
- `modelProvider` and `memory` name the `init` parameters that supply the agent's model and memory, when the
  corresponding argument is a direct reference to an `init` parameter.

```ballerina
import ballerina/ai;

public isolated class SchedulerAgent {
    *ai:FixedTypedAgent;

    private final ai:Agent agent;

    public function init(ai:Memory chatMemory, ai:ModelProvider model) returns error? {
        self.agent = check new (
            systemPrompt = {role: "Event Schedule Manager", instructions: "Organize the event schedule."},
            model = model,
            memory = chatMemory,
            tools = [self.createSchedule]
        );
    }

    public isolated function run(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns anydata|ai:Error {
        string|ai:Error answer = self.agent.run(query, sessionId, context);
        return answer;
    }

    public isolated function trace(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns ai:Trace|ai:Error => self.agent.run(query, sessionId, context);

    @ai:AgentTool
    isolated function createSchedule(string eventName) returns string => "scheduled";
}
```

### 5.8. Traces and evaluation

An `ai:Trace` records a complete agent execution:
- the user message
- every iteration, with the history sent to the model and the outputs it produced
- the tool calls requested by the model, excluding calls rejected during human approval
- the schemas of the agent's tools
- the final output
- the start and end times

A trace is obtained by calling `run` with `ai:Trace` as the expected type, or by calling `trace` on an
`ai:FixedTypedAgent`.

```ballerina
public type Trace record {|
    string id;
    ChatUserMessage userMessage;
    Iteration[] iterations;
    ChatAssistantMessage|Error output;
    FunctionCall[] toolCalls?;
    ToolSchema[] tools;
    time:Utc startTime;
    time:Utc endTime;
|};

public type Iteration record {|
    ChatMessage[] history;
    (ChatAssistantMessage|ChatFunctionMessage|Error)[] output;
    time:Utc startTime;
    time:Utc endTime;
|};

public type ToolSchema record {|
    string name;
    string description;
    map<json> parametersSchema?;
|};
```

Each `ai:Iteration` usually corresponds to one reasoning-action cycle. Its `output` contains one entry per tool
call executed in the cycle, or a single assistant message or error. A cycle that pauses for human approval is
recorded as an iteration whose only output is the `ai:ApprovalRequiredError`, and each resume adds an iteration for
the resolved batch of tool calls without a model call, so such a cycle spans two or more iterations. When a tool
call fails with an `ai:UnauthorizedError`, the iteration's output stops at the failing call, even if later calls
in a parallel batch were executed. The `id` of a trace identifies the logical
execution and stays the same across pauses for human approval.

To support agent evaluation, the library can load recorded traces from an evaluation dataset.

```ballerina
public type ConversationThread record {|
    string id;
    string description;
    readonly & Trace[] traces;
|};

public isolated function loadConversationThreads(string evalSetPath)
        returns map<[readonly & ConversationThread]>|Error;

public isolated function getUserQuery(Trace trace) returns string;
```

- `loadConversationThreads` reads a JSON evaluation set of the form
  `{"id": ..., "name": ..., "description": ..., "threads": [...]}`, where each thread has an `id`, a
  `description`, and a list of `traces`. It returns the threads keyed by thread ID. If the file cannot be read or
  parsed, it returns an `ai:Error`.
- `getUserQuery` returns the user query of a trace as a string.

```ballerina
import ballerina/ai;
import ballerina/test;

@test:Config {dataProvider: loadThreads}
function testAgent(ai:ConversationThread thread) returns error? {
    foreach ai:Trace expected in thread.traces {
        string answer = check mathTutorAgent.run(ai:getUserQuery(expected), sessionId = thread.id);
        // compare `answer` with `expected.output`
    }
}

isolated function loadThreads() returns map<[readonly & ai:ConversationThread]>|error =>
    ai:loadConversationThreads("tests/resources/eval-set.json");
```

## 6. Memory

Memory stores the conversation history of an agent per session, so that the context of earlier turns is
available in later runs. Agents use memory as described in [Section 5.3](#53-sessions).

### 6.1. Memory type

```ballerina
public type Memory isolated object {
    public isolated function get(string sessionId) returns ChatMessage[]|MemoryError;
    public isolated function update(string sessionId, ChatMessage|ChatMessage[] message) returns MemoryError?;
    public isolated function delete(string sessionId) returns MemoryError?;
};
```

- `get`: Returns the stored messages of the session, oldest first.
- `update`: Stores one message or a batch of messages for the session. After a completed run, an agent passes a single
  batch: its system message, the user message, the tool call and tool result messages, and the final assistant
  message. A run paused for human approval writes nothing until it is resumed and completes.
- `delete`: Removes all messages of the session.

Implementations should store the system message separately from the conversation: `update` replaces any stored
system message instead of appending it, and `get` returns it first. This is not required: the agent drops any system
message returned by `get` and always sends its current system prompt first. An implementation that limits its size
should keep a tool call message and its tool result messages together.

Any implementation of `ai:Memory` can be supplied to an agent. Durable human-in-the-loop checkpoints are available
only with `ai:ShortTermMemory` (see [Section 5.5.4](#554-checkpoints)).

### 6.2. Short-term memory

`ai:ShortTermMemory` is the default memory of an agent. It keeps the messages in an `ai:ShortTermMemoryStore`
and applies an overflow strategy when the store's capacity is exceeded. It also persists human-in-the-loop
checkpoints in the same store.

```ballerina
public isolated class ShortTermMemory {
    *Memory;

    public isolated function init(ShortTermMemoryStore? store = (),
            OverflowHandlerConfiguration overflowConfiguration = <TrimOverflowHandlerConfiguration> {})
            returns MemoryError?;
    public isolated function get(string key) returns ChatMessage[]|MemoryError;
    public isolated function update(string key, ChatMessage|ChatMessage[] message) returns MemoryError?;
    public isolated function delete(string key) returns MemoryError?;
    public isolated function putCheckpoint(PendingApproval approval) returns Error?;
    public isolated function getCheckpoint(string sessionId) returns PendingApproval?|Error;
    public isolated function removeCheckpoint(string sessionId) returns Error?;
    public isolated function takeCheckpoint(string sessionId) returns PendingApproval?|Error;
}

public type OverflowHandlerConfiguration TrimOverflowHandlerConfiguration|ModelAssistedOverflowHandlerConfiguration;
```

- `store`: The backing store. If it is not provided, a new `ai:InMemoryShortTermMemoryStore` with the default
  capacity is used.
- `overflowConfiguration`: The overflow strategy. Trimming is used by default.

The capacity of the store applies to interactive messages, that is, user, assistant, and function messages. The
system message is stored separately and does not count toward the capacity. An update overflows when the number
of stored interactive messages plus the number of incoming interactive messages exceeds the capacity.

The checkpoint methods store, read, remove, and atomically claim (`takeCheckpoint`) the `ai:PendingApproval` of a
session. The agent uses them as described in [Section 5.5](#55-human-in-the-loop-approval).

If initialization fails, for example because the default model provider is not configured for model-assisted
overflow handling, `init` returns an `ai:MemoryError`.

#### 6.2.1. Trim overflow handling

```ballerina
public type TrimOverflowHandlerConfiguration record {|
    int trimCount = 1;
|};
```

On overflow, the oldest interactive messages are removed in multiples of `trimCount` until the incoming messages
fit within the capacity, and the incoming messages are then stored. When a batch of messages is added, the stored
and incoming messages are trimmed together, so a batch larger than the capacity also loses its own leading
messages. The newest message is always kept, even when `trimCount` exceeds the number of messages. `trimCount` must
be a positive integer; otherwise, the `ai:ShortTermMemory` initializer returns an `ai:MemoryError`.

#### 6.2.2. Model-assisted overflow handling

```ballerina
public type ModelAssistedOverflowHandlerConfiguration record {|
    ModelProvider model?;
    Prompt prompt = defaultSummarizationPrompt;
|};
```

On overflow, the stored interactive messages are summarized by a model.
- `model`: The model provider used for summarization. If it is not provided, the default model provider is used
  (see [Section 2](#2-model-providers)).
- `prompt`: The system prompt of the summarization call. If it is not provided, a built-in summarization prompt
  is used.

The model is called with `prompt` as the system message and a user message containing the history to summarize.
The summarized history is replaced by a single assistant message containing the summary.
- If the last message to be summarized is a user message, it is kept verbatim after the summary.
- When a batch of incoming messages overflows the capacity, the leading part of the batch is summarized together
  with the stored messages, and the trailing part is kept as is. The trailing part holds only as many messages as
  fit within the capacity alongside the summary, and never starts with a tool result message: tool results are
  summarized together with the tool call message they answer.
- If the summarization call fails, `update` returns an `ai:MemoryError`.

```ballerina
final ai:Memory memory = check new ai:ShortTermMemory(
    check new ai:InMemoryShortTermMemoryStore(20),
    overflowConfiguration = {model: summarizerModel}
);
```

### 6.3. Short-term memory store

`ai:ShortTermMemoryStore` is the storage abstraction used by `ai:ShortTermMemory`. It stores, per key, at most one
system message and a list of interactive messages, along with human-in-the-loop checkpoints. An implementation
backed by a durable store makes both the conversation history and pauses durable.

```ballerina
public type ShortTermMemoryStore isolated object {
    public isolated function getChatSystemMessage(string key) returns ChatSystemMessage|MemoryError?;
    public isolated function getChatInteractiveMessages(string key) returns ChatInteractiveMessage[]|MemoryError;
    public isolated function getAll(string key)
        returns [ChatSystemMessage, ChatInteractiveMessage...]|ChatInteractiveMessage[]|MemoryError;
    public isolated function put(string key, ChatMessage|ChatMessage[] message) returns MemoryError?;
    public isolated function removeChatSystemMessage(string key) returns MemoryError?;
    public isolated function removeChatInteractiveMessages(string key, int? count = ()) returns MemoryError?;
    public isolated function removeAll(string key) returns MemoryError?;
    public isolated function isFull(string key) returns boolean|MemoryError;
    public isolated function getCapacity() returns int;
    public isolated function putCheckpoint(PendingApproval approval) returns Error?;
    public isolated function getCheckpoint(string sessionId) returns PendingApproval?|Error;
    public isolated function removeCheckpoint(string sessionId) returns Error?;
    public isolated function takeCheckpoint(string sessionId) returns PendingApproval?|Error;
};
```

- `put` stores a system message by replacing the existing one, and appends interactive messages.
- `removeChatInteractiveMessages` removes the first `count` interactive messages, or all of them when `count` is
  `()`.
- `takeCheckpoint` must fetch and remove the checkpoint of the session atomically.

`ai:InMemoryShortTermMemoryStore` is the built-in implementation. It keeps messages and checkpoints in process
memory, so they do not survive a restart and are not shared between replicas.

```ballerina
public isolated class InMemoryShortTermMemoryStore {
    *ShortTermMemoryStore;

    public isolated function init(int size = 10) returns MemoryError?;
}
```

`size` is the capacity of interactive messages per key. It must be at least `3`; otherwise `init` returns an
`ai:MemoryError`.

### 6.4. Message window chat memory

> **Deprecated:** `ai:MessageWindowChatMemory` is deprecated and will be removed in a future release. Use
> `ai:ShortTermMemory` instead.

```ballerina
@deprecated
public isolated class MessageWindowChatMemory {
    *Memory;

    public isolated function init(int size = 10);
    public isolated function get(string sessionId) returns ChatMessage[]|MemoryError;
    public isolated function update(string sessionId, ChatMessage|ChatMessage[] message) returns MemoryError?;
    public isolated function delete(string sessionId) returns MemoryError?;
}
```

`ai:MessageWindowChatMemory` keeps a sliding window of the most recent interactive messages per session in
process memory and evicts the oldest messages when the window is full. When messages are added one at a time, the
window holds at most `size - 1` interactive messages. The system message is
stored separately from the window.

## 7. Retrieval-augmented generation

The library provides the building blocks for retrieval-augmented generation (RAG): document types, data loaders,
chunkers, embedding types, vector stores, retrievers, and knowledge bases. Each building block is defined as an
abstract object type so that other packages (for example, vector store connectors such as `ballerinax/ai.pinecone`)
can provide implementations, and the library ships one default implementation of each.

A typical ingestion flow loads documents with a `DataLoader`, ingests them into a `KnowledgeBase` (which chunks them,
generates embeddings using an `EmbeddingProvider`, and stores them in a `VectorStore`). A typical retrieval flow
queries the `KnowledgeBase`, then passes the matches to `augmentUserQuery` to build a prompt for a `ModelProvider`.

### 7.1. Documents and chunks

A `Document` is the unit of content handled by the RAG components. Every document has a `'type` discriminator, an
optional `Metadata` record, and its `content`. A `Chunk` is a document produced by splitting a larger document, and
has the same shape as a `Document`.

```ballerina
public type Document record {|
    string 'type;
    Metadata metadata?;
    anydata content;
|};

public type Chunk record {|
    *Document;
|};
```

The following concrete document and chunk types are defined. The `'type` field of each is fixed to the given value.

| Type             | `'type`        | `content`               |
|------------------|----------------|-------------------------|
| `TextDocument`   | `"text"`       | `string`                |
| `TextChunk`      | `"text-chunk"` | `string`                |
| `ImageDocument`  | `"image"`      | `Url\|byte[]`           |
| `AudioDocument`  | `"audio"`      | `Url\|byte[]`           |
| `FileDocument`   | `"file"`       | `byte[]\|Url\|FileId`   |
| `BinaryDocument` | `"binary"`     | `byte[]`                |

```ballerina
public type TextDocument record {|
    *Document;
    readonly "text" 'type = "text";
    string content;
|};

public type TextChunk record {|
    *Chunk;
    readonly "text-chunk" 'type = "text-chunk";
    string content;
|};

public type ImageDocument record {|
    *Document;
    readonly "image" 'type = "image";
    Url|byte[] content;
|};

public type AudioDocument record {|
    *Document;
    readonly "audio" 'type = "audio";
    Url|byte[] content;
|};

public type FileId record {|
    string fileId;
|};

public type FileDocument record {|
    *Document;
    readonly "file" 'type = "file";
    byte[]|Url|FileId content;
|};

public type BinaryDocument record {|
    *Document;
    readonly "binary" 'type = "binary";
    byte[] content;
|};
```

`Url` is a `string` constrained (using `@constraint:String`) to the pattern
`` [a-zA-Z][a-zA-Z0-9+.-]*://(?:[^@\s"']+@)?[^\s"']+ ``.

The `Metadata` record carries well-known fields populated by the data loaders and chunkers, and is open to any
additional `json` field. Metadata fields are the keys used by [metadata filters](#76-metadata-filters).

```ballerina
public type Metadata record {|
    string mimeType?;
    string fileName?;
    decimal fileSize?;
    time:Utc createdAt?;
    time:Utc modifiedAt?;
    int index?;
    int id?;
    int prev?;
    string header?;
    string language?;
    string header1?;
    string header2?;
    string header3?;
    string header4?;
    string header5?;
    string header6?;
    json...;
|};
```

```ballerina
ai:TextDocument doc = {
    content: "Ballerina is an open-source programming language for the cloud.",
    metadata: {fileName: "intro.txt", "category": "overview"}
};
```

### 7.2. Data loaders

A `DataLoader` loads one or more documents from a source.

```ballerina
public type DataLoader isolated object {
    public isolated function load() returns Document[]|Document|Error;
};
```

`TextDataLoader` loads files from the local file system as `TextDocument` values. The supported file extensions are
`pdf`, `docx`, `pptx`, `html`, `htm`, and `md`, matched case-insensitively against the extension of the file name.
The `init` method returns an `ai:Error` if any of the given paths does
not exist. The `load` method returns an `ai:Error` for a file with an unsupported extension. When a single path is
given, `load` returns a single `Document`; otherwise it returns a `Document[]`.

```ballerina
public isolated class TextDataLoader {
    *DataLoader;

    public isolated function init(string... paths) returns Error?;
    public isolated function load() returns Document[]|Document|Error;
}
```

```ballerina
ai:TextDataLoader loader = check new ("./docs/leave-policy.pdf", "./docs/handbook.md");
ai:Document|ai:Document[] documents = check loader.load();
```

### 7.3. Chunkers

A `Chunker` splits a document into chunks.

```ballerina
public type Chunker isolated object {
    public isolated function chunk(Document document) returns Chunk[]|Error;
};
```

The library provides three chunkers. Each starts splitting with the configured strategy and recursively falls back to
a finer-grained strategy when a piece exceeds `maxChunkSize` characters. `maxOverlapSize` is the maximum number of
characters reused from the end of the previous chunk when creating the next one. For `ai:GenericRecursiveChunker`,
the overlap is made of complete sentences taken in reverse from the previous chunk. For `ai:MarkdownChunker` and
`ai:HtmlChunker`, the overlap is the last piece of the previous chunk, split further by full stops, then words, then
characters until it fits within `maxOverlapSize`.

```ballerina
public isolated class GenericRecursiveChunker {
    *Chunker;

    public isolated function init(int maxChunkSize = 200, int maxOverlapSize = 40,
            RecursiveChunkStrategy strategy = PARAGRAPH);
    public isolated function chunk(Document document) returns Chunk[]|Error;
}

public isolated class MarkdownChunker {
    *Chunker;

    public isolated function init(int maxChunkSize = 200, int maxOverlapSize = 40,
            MarkdownChunkStrategy strategy = MARKDOWN_HEADER);
    public isolated function chunk(Document document) returns Chunk[]|Error;
}

public isolated class HtmlChunker {
    *Chunker;

    public isolated function init(int maxChunkSize = 200, int maxOverlapSize = 40,
            HtmlChunkStrategy strategy = HTML_HEADER);
    public isolated function chunk(Document document) returns Chunk[]|Error;
}
```

The same functionality is available as functions. `chunkDocumentRecursively` accepts only a `TextDocument`, a
`TextChunk`, or a `string`, and returns an `ai:Error` for any other document.

```ballerina
public isolated function chunkDocumentRecursively(Document|string document, int maxChunkSize = 200,
        int maxOverlapSize = 40, RecursiveChunkStrategy strategy = PARAGRAPH) returns Chunk[]|Error;

public isolated function chunkMarkdownDocument(Document document, int maxChunkSize, int maxOverlapSize,
        MarkdownChunkStrategy strategy = MARKDOWN_HEADER) returns TextChunk[]|Error;

public isolated function chunkHtmlDocument(Document document, int maxChunkSize, int maxOverlapSize,
        HtmlChunkStrategy strategy = HTML_HEADER) returns TextChunk[]|Error;
```

#### 7.3.1. Chunking strategies

```ballerina
public enum RecursiveChunkStrategy {
    CHARACTER,
    WORD,
    LINE,
    SENTENCE,
    PARAGRAPH
}
```

| Strategy    | Boundary                                                    | Fallback order              |
|-------------|-------------------------------------------------------------|-----------------------------|
| `PARAGRAPH` | Two or more newline characters (`"\n\n"`)                   | `SENTENCE`, `WORD`, `CHARACTER` |
| `SENTENCE`  | Sentence boundaries detected by the OpenNLP sentence detector | `WORD`, `CHARACTER`       |
| `LINE`      | One or more newline characters (`"\n"`)                     | `SENTENCE`, `WORD`, `CHARACTER` |
| `WORD`      | One or more whitespace characters                           | `CHARACTER`                 |
| `CHARACTER` | Individual characters                                       | —                           |

When multiple units fit within the limit, they are joined using the separator of the unit: `"\n\n"` for paragraphs,
`"\n"` for lines, and a single space for sentences and words.

```ballerina
public enum MarkdownChunkStrategy {
    MARKDOWN_HEADER,
    CODE_BLOCK,
    HORIZONTAL_LINE,
    PARAGRAPH,
    LINE,
    SENTENCE,
    WORD,
    CHARACTER
}
```

- `MARKDOWN_HEADER` splits by headers, starting with `h2` and recursively falling back to `h3` through `h6`, then to
  `CODE_BLOCK`, `HORIZONTAL_LINE`, `PARAGRAPH`, `LINE`, `SENTENCE`, `WORD`, and `CHARACTER`, in that order.
- `CODE_BLOCK` splits by fenced code blocks. Chunks produced from a code block are not merged with other chunks, and
  carry `type` metadata with the value `code_block` and `language` metadata with the language of the block, or
  `unknown` when the block does not specify one.
- `HORIZONTAL_LINE` splits by horizontal rules (`***`, `---`, `___`), falling back to `PARAGRAPH`, `LINE`,
  `SENTENCE`, `WORD`, and `CHARACTER`.

```ballerina
public enum HtmlChunkStrategy {
    HTML_HEADER,
    HTML_PARAGRAPH,
    HTML_LINE,
    SENTENCE,
    WORD,
    CHARACTER
}
```

- `HTML_HEADER` splits by `<h1>` through `<h6>`, then falls back to `HTML_PARAGRAPH`, `HTML_LINE`, `SENTENCE`, `WORD`,
  and `CHARACTER`, in that order.
- `HTML_PARAGRAPH` splits by `<p>` elements, then falls back to `HTML_LINE`, `SENTENCE`, `WORD`, and `CHARACTER`.
- `HTML_LINE` splits by the literal text `<br>` (other forms such as `<br/>` are not matched), then falls back to `SENTENCE`, `WORD`, and `CHARACTER`.

In `ai:MarkdownChunker` and `ai:HtmlChunker`, `SENTENCE` splits at full stops (`.`), unlike `ai:GenericRecursiveChunker`,
which detects sentence boundaries with OpenNLP.

#### 7.3.2. Automatic and disabled chunking

A `VectorKnowledgeBase` accepts a `Chunker`, or one of the following constants, as its chunker configuration.

```ballerina
public const AUTO = "AUTO";
public const DISABLE = "DISABLE";
```

- `AUTO` selects a chunker per document: a `MarkdownChunker` when `metadata.mimeType` is `"text/markdown"`, an
  `HtmlChunker` when it is `"text/html"`; otherwise, a `MarkdownChunker` when the extension of `metadata.fileName` is
  `md`, an `HtmlChunker` when it is `html` or `htm` (ignoring case), and a `GenericRecursiveChunker` in all other cases. Each selected chunker
  uses its default configuration.
- `DISABLE` performs no chunking; each document is stored as a single chunk.

```ballerina
ai:Chunker chunker = new ai:MarkdownChunker(maxChunkSize = 500, maxOverlapSize = 50);
ai:Chunk[] chunks = check chunker.chunk(markdownDoc);
```

### 7.4. Embeddings and vectors

An embedding is the vector representation of a chunk, produced by an
[embedding provider](#3-embedding-providers). Dense, sparse, and hybrid representations are supported.

```ballerina
public type Vector float[];

public type SparseVector record {|
    int[] indices;
    Vector values;
|};

public type HybridVector record {|
    Vector dense;
    SparseVector sparse;
|};

public type Embedding Vector|SparseVector|HybridVector;
```

The following enums let vector store implementations expose their query mode and similarity metric as configuration.

```ballerina
public enum VectorStoreQueryMode {
    DENSE,
    SPARSE,
    HYBRID
}

public enum SimilarityMetric {
    COSINE,
    EUCLIDEAN,
    DOT_PRODUCT
}
```

### 7.5. Vector store

A `VectorStore` persists vector entries and searches them by similarity and/or metadata.

```ballerina
public type VectorStore distinct isolated object {
    public isolated function add(VectorEntry[] entries) returns Error?;
    public isolated function query(VectorStoreQuery query) returns VectorMatch[]|Error;
    public isolated function delete(string|string[] ids) returns Error?;
};

public type VectorEntry record {|
    string id?;
    Embedding embedding;
    Chunk chunk;
|};

public type VectorMatch record {|
    *VectorEntry;
    float similarityScore;
|};

public type VectorStoreQuery record {|
    Embedding embedding?;
    MetadataFilters filters?;
    int topK = 10;
|};
```

A `VectorStoreQuery` may specify an `embedding`, `filters`, or both. If neither is specified, all entries are
returned, subject to `topK`. Setting `topK` to `-1` returns all matching entries.

#### 7.5.1. In-memory vector store

`InMemoryVectorStore` keeps entries in memory and is intended for development and testing. Its behavior is as follows.

- Only dense vectors (`Vector`) are supported. `add` and `query` return an `ai:Error` if a sparse or hybrid embedding
  is given.
- `add` generates a random UUID as the `id` of an entry without one, and replaces an existing entry with the same
  `id`.
- `delete` returns an `ai:Error` if any of the given ids is not found, in which case no entry is deleted. An id
  given more than once deletes its entry once.
- When the query has an `embedding`, matches are ordered from the closest to the farthest. For `COSINE` and
  `DOT_PRODUCT`, `similarityScore` is the similarity, in descending order; for `EUCLIDEAN`, it is the distance, in
  ascending order. When the query has no `embedding`, `similarityScore` is `0.0`.
- When the query has `filters`, only entries whose chunk metadata satisfies the filters are returned. An entry with no
  metadata never satisfies a filter.
- A `topK` value less than `1` returns all matching entries.

```ballerina
public distinct isolated class InMemoryVectorStore {
    *VectorStore;

    public isolated function init(SimilarityMetric similarityMetric = COSINE) returns Error?;
    public isolated function add(VectorEntry[] entries) returns Error?;
    public isolated function query(VectorStoreQuery query) returns VectorMatch[]|Error;
    public isolated function delete(string|string[] ids) returns Error?;
}
```

```ballerina
ai:VectorStore vectorStore = check new ai:InMemoryVectorStore();
```

### 7.6. Metadata filters

Metadata filters restrict vector store queries, retrievals, and deletions to the chunks whose metadata matches a
condition. A `MetadataFilter` compares a single metadata field against a value; `MetadataFilters` combines filters, or
nested `MetadataFilters`, with `AND` or `OR`.

```ballerina
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

public enum MetadataFilterCondition {
    AND = "and",
    OR = "or"
}

public type MetadataFilter record {|
    string key;
    MetadataFilterOperator operator = EQUAL;
    json value;
|};

public type MetadataFilters record {|
    (MetadataFilters|MetadataFilter)[] filters;
    MetadataFilterCondition condition = AND;
|};
```

In the `InMemoryVectorStore`, a filter on a key that is absent from the metadata evaluates to `false`. `IN` and
`NOT_IN` expect `value` to be a JSON array. The ordering operators (`>`, `<`, `>=`, `<=`) compare both operands as
`decimal` values, and the query returns an `ai:Error` if either operand cannot be converted to `decimal`. Other vector
store implementations translate the filters into the query language of the underlying store.

```ballerina
ai:MetadataFilters filters = {
    filters: [
        {key: "category", value: "policy"},
        {key: "year", operator: ai:GREATER_THAN_OR_EQUAL, value: 2024}
    ],
    condition: ai:AND
};
```

### 7.7. Retriever

A `Retriever` returns the chunks most relevant to a text query.

```ballerina
public type Retriever distinct isolated object {
    public isolated function retrieve(string query, int maxLimit, MetadataFilters? filters = ())
        returns QueryMatch[]|Error;
};

public type QueryMatch record {|
    Chunk chunk;
    float similarityScore;
|};
```

`VectorRetriever` embeds the query as a `TextChunk` using the given `EmbeddingProvider`, queries the given
`VectorStore` with that embedding, the filters, and `topK`, and returns the matched chunks with their similarity
scores. A `topK` of `-1` returns all matching entries.

```ballerina
public distinct isolated class VectorRetriever {
    *Retriever;

    public isolated function init(VectorStore vectorStore, EmbeddingProvider embeddingModel);
    public isolated function retrieve(string query, int topK = 10, MetadataFilters? filters = ())
        returns QueryMatch[]|Error;
}
```

### 7.8. Knowledge base

A `KnowledgeBase` manages the ingestion, retrieval, and deletion of content.

```ballerina
public type KnowledgeBase distinct isolated object {
    public isolated function ingest(Chunk[]|Document[]|Document documents) returns Error?;
    public isolated function retrieve(string query, int maxLimit, MetadataFilters? filters = ())
        returns QueryMatch[]|Error;
    public isolated function deleteByFilter(MetadataFilters filters) returns Error?;
};
```

`VectorKnowledgeBase` is the vector-store-backed implementation.

- `ingest` chunks the input using the configured chunker (see [7.3.2](#732-automatic-and-disabled-chunking)),
  embeds all chunks with a single `batchEmbed` call, and adds the resulting entries to the vector store. It returns an
  `ai:Error` if the number of embeddings returned differs from the number of chunks.
- `retrieve` delegates to a `VectorRetriever` over the same vector store and embedding provider.
- `deleteByFilter` queries the vector store with the filters and `topK: -1`, then deletes all matched entries by id.

```ballerina
public distinct isolated class VectorKnowledgeBase {
    *KnowledgeBase;

    public isolated function init(VectorStore vectorStore, EmbeddingProvider embeddingModel,
            Chunker|AUTO|DISABLE chunker = AUTO);
    public isolated function ingest(Document|Document[]|Chunk[] documents) returns Error?;
    public isolated function retrieve(string query, int topK = 10, MetadataFilters? filters = ())
        returns QueryMatch[]|Error;
    public isolated function deleteByFilter(MetadataFilters filters) returns Error?;
}
```

```ballerina
final ai:VectorStore vectorStore = check new ai:InMemoryVectorStore();
final ai:EmbeddingProvider embeddingProvider = check ai:getDefaultEmbeddingProvider();
final ai:KnowledgeBase knowledgeBase = new ai:VectorKnowledgeBase(vectorStore, embeddingProvider);

public function main() returns error? {
    ai:DataLoader loader = check new ai:TextDataLoader("./leave-policy.md");
    check knowledgeBase.ingest(check loader.load());

    ai:QueryMatch[] matches = check knowledgeBase.retrieve("How many annual leave days do I get?", 5);
}
```

### 7.9. Augmenting user queries

`augmentUserQuery` builds a `ChatUserMessage` whose content is an `ai:Prompt` that instructs the model to answer the
question based on the given context. The context is either the chunks of the given `QueryMatch` values, or the given
documents.

```ballerina
public isolated function augmentUserQuery(QueryMatch[]|Document[] context, string query) returns ChatUserMessage;
```

```ballerina
string query = "How many annual leave days do I get?";
ai:QueryMatch[] matches = check knowledgeBase.retrieve(query, 5);
ai:ChatUserMessage augmented = ai:augmentUserQuery(matches, query);
ai:ChatAssistantMessage answer = check modelProvider->chat(augmented);
```

## 8. Chat service

The library provides a listener, a service type, and a client to expose an agent as an HTTP chat service. The chat
service is built on `ballerina/http`.

### 8.1. Listener

`ai:Listener` accepts either a port number or an existing `http:Listener`. When a port is given, a new
`http:Listener` is created on that port; the default port is `8090`. Passing an `http:Listener` allows the chat
service to share a port with other HTTP services, and to use any `http:ListenerConfiguration`.

The listener implements the standard listener life cycle methods. `attach` does not attach the user's service
directly; it attaches an internal dispatcher service to the underlying `http:Listener` that forwards each `chat` and
`decision` request to the user's service, and maps human-in-the-loop errors to HTTP responses as described in
[8.4](#84-approval-error-responses).

```ballerina
public class Listener {
    public function init(int|http:Listener listenOn = 8090) returns error?;
    public isolated function attach(ChatService chatService, string[]|string? name = ()) returns error?;
    public isolated function detach(ChatService chatService) returns error?;
    public isolated function 'start() returns error?;
    public isolated function gracefulStop() returns error?;
    public isolated function immediateStop() returns error?;
}
```

```ballerina
// Listens on the default port 8090.
listener ai:Listener chatListener = new;

// Shares the port of an existing HTTP listener.
listener http:Listener httpListener = new (9090);
listener ai:Listener sharedChatListener = new (httpListener);
```

### 8.2. Chat service

`ai:ChatService` is the service type attached to an `ai:Listener`.

```ballerina
public type ChatService distinct service object {
    *http:Service;
};
```

The type itself does not declare any resource. The compiler plugin enforces the following shape on a service
declaration attached to an `ai:Listener`. A service object attached programmatically through `attach` is not
checked at compile time, and an unsupported shape surfaces as an error at runtime.

- The service must declare a `post chat` resource. Its payload parameter must accept an `ai:ChatReqMessage`.
- The service may declare a `post decision` resource to resume runs paused for human approval. Its payload parameter
  must accept an `ai:DecisionMessage`.
- Each of these resources must declare its payload as the first parameter, annotated with `@http:Payload`, optionally
  followed by an `http:Headers` parameter. No other parameter is allowed.
- Each of these resources must return a value assignable to `ai:ChatRespMessage|error`.
- Any other resource is a compilation error. An endpoint such as a health check must be attached to an `http:Service`
  on the `http:Listener` passed to the `ai:Listener`.

```ballerina
final ai:Agent agent = check new (
    systemPrompt = {role: "Assistant", instructions: "You are a helpful assistant."},
    model = check ai:getDefaultModelProvider(),
    tools = [getWeather]
);

service /assistant on new ai:Listener(8090) {
    resource function post chat(@http:Payload ai:ChatReqMessage request, http:Headers headers)
            returns ai:ChatRespMessage|error {
        string answer = check agent.run(request.message, request.sessionId);
        return {message: answer};
    }

    resource function post decision(@http:Payload ai:DecisionMessage request) returns ai:ChatRespMessage|error {
        ai:Resume resume = {decisions: request.decisions};
        string answer = check agent.run(resume, request.sessionId);
        return {message: answer};
    }
}
```

### 8.3. Chat messages

```ballerina
public type ChatReqMessage record {|
    string sessionId;
    string message;
|};

public type ChatRespMessage record {|
    string message;
|};

public type DecisionMessage readonly & record {|
    string sessionId;
    map<HumanDecision> decisions;
|};
```

- `ChatReqMessage` is the payload of the `chat` resource. `sessionId` identifies the conversation; `message` is the
  user's message.
- `ChatRespMessage` is the response of both resources.
- `DecisionMessage` is the payload of the `decision` resource. `decisions` maps the `id` of each pending
  `ApprovalRequest` to the human's `HumanDecision` (see [5.5](#55-human-in-the-loop-approval)).

### 8.4. Approval error responses

A `chat` or `decision` resource may return the error produced by `Agent.run` without any HTTP-specific handling. The
listener maps the following errors to HTTP responses; any other result, including any other error, is passed through
to the `http` module unchanged.

| Returned error            | HTTP status       | Response body                                                        |
|---------------------------|-------------------|----------------------------------------------------------------------|
| `ApprovalRequiredError`   | `403 Forbidden`   | `{"requests": ApprovalRequest[]}`, from the detail of the error      |
| `ApprovalNotFoundError`   | `404 Not Found`   | `{"errorType": "ApprovalNotFoundError", "message": <error message>}` |
| `UnknownApprovalIdError`  | `400 Bad Request` | `{"errorType": "UnknownApprovalIdError", "message": <error message>}`|

`errorType` is a stable discriminator for clients to branch on; `message` is human-readable text that may change.

A client that receives a `403` response collects a decision for each pending request and sends them to the
`decision` resource to resume the run.

### 8.5. Chat client

`ai:ChatClient` invokes a chat service.

```ballerina
public type ChatClientConfiguration record {|
    *http:ClientConfiguration;
|};

public isolated client class ChatClient {
    public function init(string serviceUrl, *ChatClientConfiguration clientConfig) returns error?;
    isolated resource function post chat(ChatReqMessage request) returns ChatRespMessage|error;
    isolated resource function post decision(DecisionMessage request) returns ChatRespMessage|error;
}
```

The `decision` resource is meaningful only against a service that declares a `decision` resource; otherwise the
service responds with `404`.

```ballerina
ai:ChatClient chatClient = check new ("http://localhost:8090/assistant");
ai:ChatRespMessage response = check chatClient->/chat.post({sessionId: "session-1", message: "Hi!"});
```

## 9. Observability

The `ballerina/ai.observe` module provides tracing spans for AI operations. The `ballerina/ai` module and the provider
connectors use it to record spans for model calls, embedding calls, agent creation and invocation, tool execution,
knowledge base operations, agent identity operations, and human-in-the-loop approvals. The spans follow the
OpenTelemetry semantic conventions for generative AI: span attributes use the `gen_ai.*` namespace (for example,
`gen_ai.operation.name`, `gen_ai.request.model`, `gen_ai.usage.input_tokens`), and attributes and operations that the
conventions do not define (knowledge base, agent identity, and human-in-the-loop) use the same namespace.

Spans are recorded only when tracing is enabled through Ballerina observability (`observe:isTracingEnabled()`). When
tracing is disabled, creating a span and calling its methods have no effect.

```ballerina
import ballerina/ai.observe;
```

### 9.1. Spans

Every span is an `AiSpan` and is completed by calling `close`. Passing an error to `close` marks the span as failed. `AiSpan` also declares a module-private `addTag` method over the module-private `GenAiTagNames` enum, so
the type cannot be implemented outside the `ai.observe` module.

```ballerina
public type AiSpan distinct isolated object {
    isolated function addTag(GenAiTagNames key, anydata value);
    public isolated function close(error? err = ());
};

public enum OutputType {
    TEXT = "text",
    JSON = "json"
}

public enum ToolType {
    FUNCTION = "function",
    EXTENTION = "extension"
}
```

The model provider spans implement `LlmSpan`, which is used by provider connectors to record the request and response
of a model call.

```ballerina
public type LlmSpan distinct isolated object {
    *AiSpan;
    public isolated function addProvider(string providerName);
    public isolated function addTemperature(float|decimal temperature);
    public isolated function addInputMessages(json messages);
    public isolated function addOutputMessages(json messages);
    public isolated function addResponseModel(string modelName);
    public isolated function addResponseId(string|int id);
    public isolated function addInputTokenCount(int count);
    public isolated function addOutputTokenCount(int count);
    public isolated function addFinishReason(string|string[] reason);
    public isolated function addOutputType(OutputType outputType);
    public isolated function addStopSequence(string|string[] stopSequence);
    public isolated function addTools(json[] tools);
};
```

The following span classes are defined. Each class is created through the corresponding factory function in
[9.2](#92-span-factory-functions), and has a `close(error? err = ())` method in addition to the methods listed.

| Span class                      | Operation                     | Methods                                                                                                   |
|---------------------------------|-------------------------------|-----------------------------------------------------------------------------------------------------------|
| `ChatSpan`                      | `chat`                        | `LlmSpan` methods                                                                                         |
| `GenerateContentSpan`           | `generate_content`            | `LlmSpan` methods                                                                                         |
| `EmbeddingSpan`                 | `embeddings`                  | `addResponseModel`, `addProvider`, `addInputContent`, `addInputTokenCount`                                |
| `CreateAgentSpan`               | `create_agent`                | `addId`, `addSystemInstructions`, `addTools`                                                              |
| `InvokeAgentSpan`               | `invoke_agent`                | `addId`, `addSystemInstruction`, `addSessionId`, `addInput`, `addOutput`                                  |
| `ExecuteToolSpan`               | `execute_tool`                | `addId`, `addDescription`, `addType`, `addArguments`, `addOutput`, `addToolKitName`                       |
| `CreateKnowledgeBaseSpan`       | `create_knowledge_base`       | `addId`                                                                                                   |
| `KnowledgeBaseIngestSpan`       | `knowledge_base_ingest`       | `addId`, `addInputChunks`                                                                                 |
| `KnowledgeBaseRetrieveSpan`     | `knowledge_base_retrieve`     | `addId`, `addInputQuery`, `addOutput`, `addLimit`, `addFilter`                                            |
| `CreateAgentIdentitySpan`       | `create_agent_identity`       | `addId`                                                                                                   |
| `InvokeAuthorizeEndpointSpan`   | `invoke_authorize_endpoint`   | `addProviderUrl`, `addAuthRequestDetails`                                                                 |
| `AgentAuthenticationSpan`       | `agent_authentication`        | `addAgentIdentity`                                                                                        |
| `ExchangeTokenSpan`             | `exchange_token`              | `addExchangeDetails`                                                                                      |
| `ValidateTokenSpan`             | `validate_token`              | `addValidationResult`                                                                                     |
| `ValidateToolAuthorizationSpan` | `validate_tool_authorization` | `addScopeCheck`                                                                                           |
| `RequestHumanApprovalSpan`      | `request_human_approval`      | `addPendingCount`, `addRequests`                                                                          |
| `ResolveHumanApprovalSpan`      | `resolve_human_approval`      | `addDecisions`                                                                                            |

The span name is usually the operation name followed by the name passed to the factory function (for example,
`chat gpt-4o-mini` or `invoke_agent Assistant`). The following agent identity spans are named differently:
`agent_authentication Flow: <flowId>`, `validate_token from <provider>`, `validate_tool_authorization: <toolName>`,
and `exchange_token`.

### 9.2. Span factory functions

Each factory function starts a span and registers it as the current AI span of the current execution context.

```ballerina
public isolated function createCreateAgentSpan(string agentName) returns CreateAgentSpan;
public isolated function createInvokeAgentSpan(string agentName) returns InvokeAgentSpan;
public isolated function createExecuteToolSpan(string toolName) returns ExecuteToolSpan;
public isolated function createEmbeddingSpan(string embeddingModel) returns EmbeddingSpan;
public isolated function createChatSpan(string llmModel) returns ChatSpan;
public isolated function createGenerateContentSpan(string llmModel) returns GenerateContentSpan;
public isolated function createCreateKnowledgeBaseSpan(string kbName) returns CreateKnowledgeBaseSpan;
public isolated function createKnowledgeBaseIngestSpan(string kbName) returns KnowledgeBaseIngestSpan;
public isolated function createKnowledgeBaseRetrieveSpan(string kbName) returns KnowledgeBaseRetrieveSpan;
public isolated function createCreateAgentIdentitySpan(string agentName) returns CreateAgentIdentitySpan;
public isolated function createInvokeAuthorizeEndpointSpan(string organization) returns InvokeAuthorizeEndpointSpan;
public isolated function createAgentAuthenticationSpan(string flowId) returns AgentAuthenticationSpan;
public isolated function createExchangeTokenSpan() returns ExchangeTokenSpan;
public isolated function createValidateTokenSpan(string provider) returns ValidateTokenSpan;
public isolated function createValidateToolAuthorizationSpan(string toolName) returns ValidateToolAuthorizationSpan;
public isolated function createRequestHumanApprovalSpan(string sessionId) returns RequestHumanApprovalSpan;
public isolated function createResolveHumanApprovalSpan(string sessionId) returns ResolveHumanApprovalSpan;
```

A model provider connector records a chat call as follows.

```ballerina
observe:ChatSpan span = observe:createChatSpan(modelName);
span.addProvider("openai");
span.addInputMessages(messages.toJson());
ai:ChatAssistantMessage|ai:Error response = callModel(messages);
if response is ai:Error {
    span.close(response);
    return response;
}
span.addOutputMessages(response.toJson());
span.close();
```

### 9.3. Current span

`getCurrentAiSpan` returns the AI span registered for the current execution context, or `()` if tracing is disabled
or no AI span is active. Closing a span removes it as the current AI span.

```ballerina
public isolated function getCurrentAiSpan() returns AiSpan?;
```

## 10. Errors

### 10.1. Error hierarchy

All errors returned by the library are subtypes of `ai:Error`, except those of `ai:Listener` and `ai:ChatClient`,
which return `error` and may return errors of the `http` module.

```
Error
├── OpenApiParsingError
│   ├── ParsingStackOverflowError
│   ├── UnsupportedSerializationError
│   ├── UnsupportedOpenApiVersion
│   ├── InvalidReferenceError
│   ├── IncompleteSpecificationError
│   ├── UnsupportedMediaTypeError
│   └── InvalidParameterDefinition
├── LlmError
│   ├── LlmInvalidResponseError
│   ├── LlmConnectionError
│   └── LlmInvalidGenerationError
│       ├── ToolNotFoundError
│       └── ToolInvalidInputError
│           └── MissingHttpParameterError
├── TaskCompletedError
├── HttpServiceToolKitError
│   └── HttpResponseParsingError
├── ToolExecutionError
│   ├── UnauthorizedError
│   ├── ToolInvalidOutputError
│   ├── TokenAcquisitionError
│   └── TokenValidationError
│       └── InsufficientScopeError
├── MaxIterationExceededError
├── MemoryError
├── ApprovalRequiredError
├── ApprovalNotFoundError
└── UnknownApprovalIdError
```

```ballerina
public type Error distinct error;

public type OpenApiParsingError distinct Error;
public type ParsingStackOverflowError distinct OpenApiParsingError;
public type UnsupportedSerializationError distinct OpenApiParsingError;
public type UnsupportedOpenApiVersion distinct OpenApiParsingError;
public type InvalidReferenceError distinct OpenApiParsingError;
public type IncompleteSpecificationError distinct OpenApiParsingError;
public type UnsupportedMediaTypeError distinct OpenApiParsingError;
public type InvalidParameterDefinition distinct OpenApiParsingError;

public type LlmError distinct Error;
public type LlmInvalidResponseError distinct LlmError;
public type LlmInvalidGenerationError distinct LlmError;
public type LlmConnectionError distinct LlmError;
public type ToolNotFoundError distinct LlmInvalidGenerationError;
public type ToolInvalidInputError distinct LlmInvalidGenerationError;
public type MissingHttpParameterError distinct ToolInvalidInputError;

public type TaskCompletedError distinct Error;

public type HttpServiceToolKitError distinct Error;
public type HttpResponseParsingError distinct HttpServiceToolKitError;

public type ToolExecutionError distinct Error;
public type UnauthorizedError distinct ToolExecutionError;
public type ToolInvalidOutputError distinct ToolExecutionError;
public type TokenAcquisitionError distinct ToolExecutionError;
public type TokenValidationError distinct ToolExecutionError;
public type InsufficientScopeError distinct TokenValidationError;

public type MaxIterationExceededError distinct (Error & error<record {|(ExecutionResult|ExecutionError|Error)[] steps;|}>);

public type MemoryError distinct Error;

public type ApprovalRequiredError distinct (Error & error<record {| ApprovalRequest[] requests; |}>);
public type ApprovalNotFoundError distinct Error;
public type UnknownApprovalIdError distinct Error;
```

### 10.2. Error types

| Error                           | Returned when                                                                                                         | Detail                                          |
|---------------------------------|-----------------------------------------------------------------------------------------------------------------------|-------------------------------------------------|
| `Error`                         | Any failure not covered by a more specific type, such as an invalid argument, or a missing `wso2ProviderConfig`.      | —                                               |
| `OpenApiParsingError`           | An OpenAPI specification cannot be parsed into HTTP tools.                                                            | —                                               |
| `ParsingStackOverflowError`     | The specification is too deeply nested or contains cyclic references.                                                 | —                                               |
| `UnsupportedSerializationError` | A parameter uses an unsupported serialization style.                                                                  | —                                               |
| `UnsupportedOpenApiVersion`     | The specification version is not 3.0.x or 3.1.x.                                                                      | —                                               |
| `InvalidReferenceError`         | The specification contains an invalid or broken `$ref`.                                                               | —                                               |
| `IncompleteSpecificationError`  | The specification is missing required content.                                                                        | —                                               |
| `UnsupportedMediaTypeError`     | A request body uses an unsupported media type.                                                                        | —                                               |
| `InvalidParameterDefinition`    | A parameter definition includes neither `schema` nor `content`.                                                       | —                                               |
| `LlmError`                      | A model call fails.                                                                                                   | —                                               |
| `LlmConnectionError`            | The model provider cannot be reached, or returns an error response.                                                   | —                                               |
| `LlmInvalidResponseError`       | The model returns an unexpected response, such as one with no choices.                                                | —                                               |
| `LlmInvalidGenerationError`     | The model output cannot be interpreted, such as a response that cannot be parsed into a tool call or message.         | —                                               |
| `ToolNotFoundError`             | The model requests a tool that is not registered with the agent.                                                      | —                                               |
| `ToolInvalidInputError`         | The model provides arguments that do not match the input schema of the tool.                                          | —                                               |
| `MissingHttpParameterError`     | The model omits a path parameter of an HTTP tool. A missing query parameter is omitted from the request.             | —                                               |
| `TaskCompletedError`            | The agent is asked to reason further after it has already produced its final answer.                                  | —                                               |
| `HttpServiceToolKitError`       | An `HttpServiceToolKit` fails to execute an HTTP tool.                                                                | —                                               |
| `HttpResponseParsingError`      | The response of an HTTP tool cannot be parsed.                                                                        | —                                               |
| `ToolExecutionError`            | A tool fails during execution.                                                                                        | —                                               |
| `UnauthorizedError`             | A tool call is rejected because the agent is not authorized to call the tool.                                         | —                                               |
| `ToolInvalidOutputError`        | A tool returns a value that is not `anydata` or `error`.                                                              | —                                               |
| `TokenAcquisitionError`         | An access token for a tool cannot be obtained.                                                                        | —                                               |
| `TokenValidationError`          | An access token for a tool fails validation.                                                                          | —                                               |
| `InsufficientScopeError`        | An access token does not grant the scopes required by the tool.                                                       | —                                               |
| `MaxIterationExceededError`     | The agent reaches `maxIter` without producing a final answer.                                                         | `steps`: the execution steps taken              |
| `MemoryError`                   | A memory or memory store operation fails.                                                                             | —                                               |
| `ApprovalRequiredError`         | A run pauses because one or more proposed tool calls require human approval.                                          | `requests`: the pending `ApprovalRequest` values |
| `ApprovalNotFoundError`         | `Agent.run` is given a `Resume`, but no approval is pending for the session.                                          | —                                               |
| `UnknownApprovalIdError`        | A `Resume` names an id that is not among the approvals pending for the session.                                       | —                                               |
