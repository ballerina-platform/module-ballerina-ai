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

# Represents a tracing span for creating a knowledge base.
public isolated distinct class CreateKnowledgeBaseSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    # Initializes a new knowledge base creation span for the given name.
    #
    # + kbName - The name of the knowledge base being created
    isolated function init(string kbName) {
        self.baseSpan = new (string `${CREATE_KNOWLEDGE_BASE} ${kbName}`);
        self.addTag(OPERATION_NAME, CREATE_KNOWLEDGE_BASE);
        self.addTag(KNOWLEDGE_BASE_NAME, kbName);
    }

    # Records the knowledge base ID assigned after creation
    #
    # + id - The knowledge base identifier
    public isolated function addId(string|int id) {
        self.addTag(KNOWLEDGE_BASE_ID, id);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    # Closes the knowledge base creation span and records its final status.
    #
    # + err - Optional error that indicates if the operation failed
    public isolated function close(error? err = ()) {
        self.baseSpan.close(err);
    }
}

# Represents a tracing span for ingesting data into a knowledge base.
public isolated distinct class KnowledgeBaseIngestSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    # Initializes a new ingest span for the given knowledge base name.
    #
    # + kbName - The name of the knowledge base being ingested into
    isolated function init(string kbName) {
        self.baseSpan = new (string `${KNOWLEDGE_BASE_INGEST} ${kbName}`);
        self.addTag(OPERATION_NAME, KNOWLEDGE_BASE_INGEST);
        self.addTag(KNOWLEDGE_BASE_NAME, kbName);
    }

    # Records the knowledge base ID for the ingest operation.
    #
    # + id - The knowledge base identifier
    public isolated function addId(string|int id) {
        self.addTag(KNOWLEDGE_BASE_ID, id);
    }

    # Records the input chunks provied/generated for the ingest operation
    #
    # + chunks - The input chunks to be ingested
    public isolated function addInputChunks(json chunks) {
        self.addTag(KNOWLEDGE_BASE_INGEST_INPUT_CHUNKS, chunks);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    # Closes the ingest span and records its final status
    #
    # + err - Optional error that indicates if the operation failed
    public isolated function close(error? err = ()) {
        self.baseSpan.close(err);
    }
}

# Represents a tracing span for retrieving data from a knowledge base.
public isolated distinct class KnowledgeBaseRetrieveSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    # Initializes a new retrieve span for the given knowledge base name.
    #
    # + kbName - The name of the knowledge base being retrieved from
    isolated function init(string kbName) {
        self.baseSpan = new (string `${KNOWLEDGE_BASE_RETRIEVE} ${kbName}`);
        self.addTag(OPERATION_NAME, KNOWLEDGE_BASE_RETRIEVE);
        self.addTag(KNOWLEDGE_BASE_NAME, kbName);
    }

    # Records the knowledge base ID for the retrieve operation.
    #
    # + id - The knowledge base identifier
    public isolated function addId(string|int id) {
        self.addTag(KNOWLEDGE_BASE_ID, id);
    }

    # Records the input query for the retrieve operation.
    #
    # + query - The input query to retrieve data
    public isolated function addInputQuery(json query) {
        self.addTag(KNOWLEDGE_BASE_INGEST_INPUT_CHUNKS, query);
    }

    # Records the maximum limit for the retrieve operation.
    #
    # + maxLimit - The maximum number of results to retrieve
    public isolated function addLimit(int maxLimit) {
        self.addTag(KNOWLEDGE_BASE_RETRIEVE_INPUT_LIMIT, maxLimit);
    }

    # Records the filter for the retrieve operation.
    #
    # + filter - The filter criteria for retrieval
    public isolated function addFilter(json filter) {
        self.addTag(KNOWLEDGE_BASE_RETRIEVE_INPUT_FILTER, filter);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    # Closes the retrieve span and records its final status.
    #
    # + err - Optional error that indicates if the operation failed
    public isolated function close(error? err = ()) {
        self.baseSpan.close(err);
    }
}
