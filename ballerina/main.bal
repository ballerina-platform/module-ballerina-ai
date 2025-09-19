import ai.observability;

public function main() {
    observability:initTracing("http://localhost:6006/v1/traces", "test-from-ballerina");
}
