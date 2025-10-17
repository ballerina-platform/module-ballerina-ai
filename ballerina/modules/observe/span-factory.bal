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
// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).

# Creates a span representing the creation of an AI agent.
#
# + agentName - The name of the agent being created
# + return - A `CreateAgentSpan` instance representing the span
public isolated function createCreateAgentSpan(string agentName) returns CreateAgentSpan {
    CreateAgentSpan span = new (agentName);
    recordAiSpan(span);
    return span;
}

# Creates a span representing the invocation of an AI agent.
#
# + agentName - The name of the agent being invoked
# + return - An `InvokeAgentSpan` instance representing the span
public isolated function createInvokeAgentSpan(string agentName) returns InvokeAgentSpan {
    InvokeAgentSpan span = new (agentName);
    recordAiSpan(span);
    return span;
}

# Creates a span representing the execution of an AI tool.
#
# + toolName - The name of the tool being executed
# + return - An `ExecuteToolSpan` instance representing the span
public isolated function createExecuteToolSpan(string toolName) returns ExecuteToolSpan {
    ExecuteToolSpan span = new (toolName);
    recordAiSpan(span);
    return span;
}

# Creates a span representing an embedding generation operation.
#
# + embeddingModel - The embedding model name or identifier
# + return - An `EmbeddingSpan` instance representing the span
public isolated function createEmbeddingSpan(string embeddingModel) returns EmbeddingSpan {
    EmbeddingSpan span = new (embeddingModel);
    recordAiSpan(span);
    return span;
}

# Creates a span representing a chat model interaction.
#
# + llmModel - The name of the LLM or chat model used
# + return - A `ChatSpan` instance representing the span
public isolated function createChatSpan(string llmModel) returns ChatSpan {
    ChatSpan span = new (llmModel);
    recordAiSpan(span);
    return span;
}

# Creates a span representing a generate content LLM interaction.
#
# + llmModel - The name of the LLM or chat model used
# + return - A `GenerateContentSpan` instance representing the span
public isolated function createGenerateContentSpan(string llmModel) returns GenerateContentSpan {
    GenerateContentSpan span = new (llmModel);
    recordAiSpan(span);
    return span;
}

# Creates a span representing the creation of a knowledge base.
#
# + kbName - The name of the knowledge base being created
# + return - A `CreateKnowledgeBaseSpan` instance representing the span
public isolated function createCreateKnowledgeBaseSpan(string kbName) returns CreateKnowledgeBaseSpan {
    CreateKnowledgeBaseSpan span = new (kbName);
    recordAiSpan(span);
    return span;
}

# Creates a span representing ingestion into a knowledge base.
#
# + kbName - The name of the knowledge base being ingested into
# + return - A `KnowledgeBaseIngestSpan` instance representing the span
public isolated function createKnowledgeBaseIngestSpan(string kbName) returns KnowledgeBaseIngestSpan {
    KnowledgeBaseIngestSpan span = new (kbName);
    recordAiSpan(span);
    return span;
}

# Creates a span representing a retrieval operation from a knowledge base.
#
# + kbName - The name of the knowledge base being queried
# + return - A `KnowledgeBaseRetrieveSpan` instance representing the span
public isolated function createKnowledgeBaseRetrieveSpan(string kbName) returns KnowledgeBaseRetrieveSpan {
    KnowledgeBaseRetrieveSpan span = new (kbName);
    recordAiSpan(span);
    return span;
}
