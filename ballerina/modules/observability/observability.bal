import ballerina/jballerina.java;
public isolated function initTracing(string endpoint, string projectName) {
    initTracingNative(java:fromString(endpoint), java:fromString(projectName));
}

isolated function initTracingNative(handle endpoint, handle projectName) = @java:Method {
    'class: "io.ballerina.stdlib.ai.observability.Observability",
    name: "initTracing"
} external;
