public type ObservabilityProvider readonly & record {|
    function (string, string) initFunction;
    function (string) returns AgentSpan agentSpanInitFunction;
    function (string) returns EmbeddingSpan embeddingSpanInitFunction;
    function (string) returns ToolSpan toolSpanInitFunction;
    function (string, string, string) returns LLMSpan llmSpanInitFunction;
|};

public type ToolCallRequest record {
    string name;
    string id;
    json argumentJson;
};

public type ToolCallResponse record {
    string name;
    string id;
    string content;
};

public ObservabilityProvider? observabilityProvider = ();

public function setObservabilityProvider(ObservabilityProvider provider) {
    observabilityProvider = provider;
}

function getObservabilityProvider() returns ObservabilityProvider {
    if observabilityProvider == () {
        panic error("Observability provider is not set");
    }
    // JBUG: cast
    return <ObservabilityProvider>observabilityProvider;
}

public function initTracing(string endpoint, string projectName) {
    var initFunction = getObservabilityProvider().initFunction;
    initFunction(endpoint, projectName);
}

public type Span object {
    public function enter();
    public function setInput(string input);
    public function setOutput(string output);
    public function setStatus(SpanStatus status);
    public function exit();
};

public type LLMSpan object {
    *Span;

    public function addToolCallRequests(ToolCallRequest... toolCallRequests);

    public function addToolCallResponse(ToolCallResponse toolCallResponse);

    public function addIntermediateRequest(string content);

    public function addIntermediateResponse(string content);

    public function setTokenCount(int total, int prompt, int completion);
};

public type EmbeddingSpan object {
    *Span;
};

public type ToolSpan object {
    *Span;
};

public type AgentSpan object {
    *Span;
};

public function createAgentSpan(string name) returns AgentSpan {
    var agentSpanInitFunction = getObservabilityProvider().agentSpanInitFunction;
    return agentSpanInitFunction(name);
}

public function createEmbeddingSpan(string name) returns EmbeddingSpan {
    var embeddingSpanInitFunction = getObservabilityProvider().embeddingSpanInitFunction;
    return embeddingSpanInitFunction(name);
}

public function createToolSpan(string name) returns ToolSpan {
    var toolSpanInitFunction = getObservabilityProvider().toolSpanInitFunction;
    return toolSpanInitFunction(name);
}

public function createLLMSpan(string name, string modelName, string providerName) returns LLMSpan {
    var llmSpanInitFunction = getObservabilityProvider().llmSpanInitFunction;
    return llmSpanInitFunction(name, modelName, providerName);
}

public enum SpanStatus {
    OK,
    ERROR
};
