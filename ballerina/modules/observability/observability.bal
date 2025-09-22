import ballerina/jballerina.java;
import ballerina/jballerina.java.arrays;
public isolated function initTracing(string endpoint, string projectName) {
    initTracingNative(java:fromString(endpoint), java:fromString(projectName));
}

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

public type Span object {
    public function enter();
    public function setInput(string input);
    public function setOutput(string output);
    public function setStatus(SpanStatus status);
    public function exit();
};

public type SpanKind "LLM"|"EMBEDDING"|"TOOL"|"AGENT";

public class LLMSpan {
    *Span;
    private final handle spanHandle;

    function init(string name, string modelName, string providerName) {
        self.spanHandle = createLLMSpanNative(java:fromString(name), java:fromString(modelName), java:fromString(providerName));
    }

    public function getSpanHandle() returns handle {
        return self.spanHandle;
    }

    public function enter() {
        enterSpan(self.getSpanHandle());
    }

    public function exit() {
        exitSpan(self.getSpanHandle());
    }

    public function setInput(string input) {
        setInput(self.getSpanHandle(), java:fromString(input));
    }

    public function setOutput(string output) {
        setOutput(self.getSpanHandle(), java:fromString(output));
    }

    public function setStatus(SpanStatus status) {
        setStatus(self.getSpanHandle(), java:fromString(status));
    }

    public function addToolCallRequests(ToolCallRequest... toolCallRequests) {
        handle toolRequestClass = checkpanic java:getClass("io.ballerina.stdlib.ai.observability.LLMSpan$ToolRequest");
        handle toolRequestArray = arrays:newInstance(toolRequestClass, toolCallRequests.length());
        foreach int i in 0..<toolCallRequests.length() {
            handle toolRequest = createToolRequest(java:fromString(toolCallRequests[i].name), java:fromString(toolCallRequests[i].argumentJson.toJsonString()), java:fromString(toolCallRequests[i].id));
            arrays:set(toolRequestArray, i, toolRequest);
        }
        addToolCallRequests(self.getSpanHandle(), toolRequestArray);
    }

    public function addToolCallResponse(ToolCallResponse toolCallResponse) {
        handle toolResponse = createToolResponse(java:fromString(toolCallResponse.name), java:fromString(toolCallResponse.content), java:fromString(toolCallResponse.id));
        addToolCallResponse(self.getSpanHandle(), toolResponse);
    }

    public function addIntermediateRequest(string content) {
        addIntermediateRequest(self.getSpanHandle(), java:fromString(content));
    }

    public function addIntermediateResponse(string content) {
        addIntermediateResponse(self.getSpanHandle(), java:fromString(content));
    }
    public function setTokenCount(int total, int prompt, int completion) {
        setTokenCount(self.getSpanHandle(), total, prompt, completion);
    }
}

public class BaseSpan {
    *Span;
    private final handle? spanHandle;

    function init(string name, SpanKind kind) {
        handle nameHandle = java:fromString(name);
        match kind {
            "EMBEDDING" => {
                self.spanHandle = createEmbeddingSpanNative(nameHandle);
            }
            "TOOL" => {
                self.spanHandle = createToolSpanNative(nameHandle);
            }
            "AGENT" => {
                self.spanHandle = createAgentSpanNative(nameHandle);
            }
            _ => {
                self.spanHandle = ();
                panic error("Unexpected span kind: " + kind);
            }
        }
    }

    function getSpanHandle() returns handle {
        if self.spanHandle is handle {
            return <handle>self.spanHandle;
        }
        panic error("Span handle is not initialized");
    }

    public function enter() {
        enterSpan(self.getSpanHandle());
    }

    public function exit() {
        exitSpan(self.getSpanHandle());
    }

    public function setInput(string input) {
        setInput(self.getSpanHandle(), java:fromString(input));
    }

    public function setOutput(string output) {
        setOutput(self.getSpanHandle(), java:fromString(output));
    }

    public function setStatus(SpanStatus status) {
        setStatus(self.getSpanHandle(), java:fromString(status));
    }
};

public type EmbeddingSpan BaseSpan;

public type ToolSpan BaseSpan;

public type AgentSpan BaseSpan;

public function createAgentSpan(string name) returns AgentSpan {
    return new (name, "AGENT");
}

public function createEmbeddingSpan(string name) returns EmbeddingSpan {
    return new (name, "EMBEDDING");
}

public function createToolSpan(string name) returns ToolSpan {
    return new (name, "TOOL");
}

public function createLLMSpan(string name, string modelName, string providerName) returns LLMSpan {
    return new (name, modelName, providerName);
}

public enum SpanStatus {
    OK,
    ERROR
};

isolated function initTracingNative(handle endpoint, handle projectName) = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability",
    name: "initTracing"
} external;

isolated function createAgentSpanNative(handle name) returns handle = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability",
    name: "createAgentSpan"
} external;

isolated function createEmbeddingSpanNative(handle name) returns handle = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability",
    name: "createEmbeddingSpan"
} external;

isolated function createToolSpanNative(handle name) returns handle = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability",
    name: "createToolSpan"
} external;

isolated function createLLMSpanNative(handle name, handle modelName, handle providerName) returns handle = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability",
    name: "createLLMSpan"
} external;

isolated function enterSpan(handle span) = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability"
} external;

isolated function setInput(handle span, handle input) = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability"
} external;

isolated function setOutput(handle span, handle output) = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability"
} external;

isolated function setStatus(handle span, handle status) = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability"
} external;

isolated function exitSpan(handle span) = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability"
} external;

isolated function createToolRequest(handle name, handle argumentJson, handle id) returns handle = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability"
} external;


isolated function createToolResponse(handle name, handle content, handle id) returns handle = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability"
} external;

isolated function addToolCallRequests(handle span, handle toolRequestArray) = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability"
} external;

isolated function addToolCallResponse(handle span, handle toolResponse) = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability"
} external;

isolated function addIntermediateRequest(handle span, handle content) = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability"
} external;

isolated function addIntermediateResponse(handle span, handle content) = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability"
} external;

isolated function setTokenCount(handle span, int total, int prompt, int completion) = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability"
} external;
