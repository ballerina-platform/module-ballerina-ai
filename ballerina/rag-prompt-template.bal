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

# Represents a RAG prompt template that builds structured prompts from retrieved context and user queries
# for presentation to Large Language Models in RAG systems.
public type RagPromptTemplate isolated object {

    # Builds a prompt from the given context documents and query.
    #
    # + context - The array of relevant documents to include as context
    # + query - The user's original query or question
    # + return - A formatted prompt ready for LLM consumption
    public isolated function format(Document[] context, string query) returns Prompt;
};

# Default implementation of a RAG prompt template.
# Provides a standard template for combining context documents with user queries,
# creating system prompts that instruct the model to answer based on the provided context.
public isolated class DefaultRagPromptTemplate {
    *RagPromptTemplate;

    # Builds a default prompt. Creates a system prompt that includes the context documents,
    # and a user prompt containing the query. Follows common RAG patterns
    # for context-aware question answering.
    #
    # + context - The array of relevant documents to include as context
    # + query - The user's question to be answered
    # + return - A prompt containing system instructions and the user query
    public isolated function format(Document[] context, string query) returns Prompt {
        string systemPrompt = string `Answer the question based on the following provided context: `
            + string `<CONTEXT>${string:'join("\n", ...context.'map(doc => doc.content))}</CONTEXT>`;
        string userPrompt = "Question:\n" + query;
        return {systemPrompt, userPrompt};
    }
}
