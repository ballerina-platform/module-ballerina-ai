/*
 *  Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
 *
 *  WSO2 LLC. licenses this file to you under the Apache License,
 *  Version 2.0 (the "License"); you may not use this file except
 *  in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing,
 *  software distributed under the License is distributed on an
 *  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 *  KIND, either express or implied.  See the License for the
 *  specific language governing permissions and limitations
 *  under the License.
 */

package io.ballerina.stdlib.ai;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.graalvm.polyglot.Context;
import org.graalvm.python.embedding.GraalPyResources;
import org.testng.annotations.Test;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;

import static org.testng.Assert.assertEquals;
import static org.testng.Assert.assertFalse;
import static org.testng.Assert.assertNotNull;

public class TracingTest {

    private static final String PHOENIX_BASE_URL = "http://localhost:6006";
    private static final String PHOENIX_SPANS_ENDPOINT = PHOENIX_BASE_URL + "/v1/projects/test/spans?limit=100";
    private static final String PHOENIX_HEALTH_ENDPOINT = PHOENIX_BASE_URL + "/healthz";
    private static final HttpClient HTTP_CLIENT = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    @Test
    public void testTracingIntegration() throws Exception {
        // First, check if Phoenix is running using Java
        assertPhoenixIsRunning();

        // Then generate traces using Python
        generateTracesWithPython();

        // Wait for traces to be exported
        TimeUnit.SECONDS.sleep(5);

        // Finally validate traces using pure Java
        validateTracesInPhoenix();
    }

    private void generateTracesWithPython() {
        String tracingSetup = """
                import os
                from opentelemetry import trace
                from opentelemetry.semconv._incubating.attributes.gen_ai_attributes import (
                    GEN_AI_PROVIDER_NAME,
                    GEN_AI_REQUEST_MODEL,
                    GEN_AI_USAGE_INPUT_TOKENS,
                    GEN_AI_USAGE_OUTPUT_TOKENS,
                    GEN_AI_TOOL_NAME,
                    GEN_AI_AGENT_NAME
                )

                os.environ["PHOENIX_COLLECTOR_ENDPOINT"] = "http://localhost:6006/v1/traces"

                from phoenix.otel import register
                tracer_provider = register(
                    project_name="test",
                    auto_instrument=True,
                    endpoint="http://localhost:6006/v1/traces",
                )

                tracer = tracer_provider.get_tracer(__name__)

                def chat(prompt: str) -> str:
                    span_context = tracer.start_as_current_span(
                        "llm",
                        attributes={
                            GEN_AI_PROVIDER_NAME: "openai",
                            GEN_AI_REQUEST_MODEL: "gpt-4",
                            GEN_AI_USAGE_INPUT_TOKENS: 100,
                            GEN_AI_USAGE_OUTPUT_TOKENS: 50,
                        },
                        kind=trace.SpanKind.CLIENT,
                    )
                    span = span_context.__enter__()
                    try:
                        span.set_attribute("input.value", prompt)
                        response = f"LLM response to: {prompt}"
                        span.set_attribute("output.value", response)
                        return response
                    finally:
                        span_context.__exit__(None, None, None)

                def tool(input_str: str) -> str:
                    span_context = tracer.start_as_current_span(
                        "tool",
                        attributes={
                            GEN_AI_TOOL_NAME: "example_tool",
                        },
                        kind=trace.SpanKind.INTERNAL,
                    )
                    span = span_context.__enter__()
                    try:
                        span.set_attribute("input.value", input_str)
                        result = f"Tool result for: {input_str}"
                        span.set_attribute("output.value", result)
                        return result
                    finally:
                        span_context.__exit__(None, None, None)

                def agent_flow(initial_prompt: str) -> str:
                    span_context = tracer.start_as_current_span(
                        "agent",
                        attributes={
                            GEN_AI_AGENT_NAME: "simple_agent",
                        },
                        kind=trace.SpanKind.INTERNAL,
                    )
                    span = span_context.__enter__()
                    try:
                        span.set_attribute("input.value", initial_prompt)
                        current_state = initial_prompt
                        current_state = chat(current_state)
                        tool_input = "extract info from: " + current_state
                        current_state = tool(tool_input)
                        final_response = chat(current_state)
                        span.set_attribute("output.value", final_response)
                        return final_response
                    finally:
                        span_context.__exit__(None, None, None)
                """;

        String traceGenerationCode = """
                import time

                # Generate traces
                initial_prompt = "Hi how are you?"
                result = agent_flow(initial_prompt)

                # Generate additional traces
                chat_result = chat("test prompt")
                tool_result = tool("test input")

                # Wait for traces to be exported
                time.sleep(2)

                print("Traces generated successfully")
                """;

        try (Context cx = GraalPyResources.createContext()) {
            cx.eval("python", tracingSetup);
            cx.eval("python", traceGenerationCode);
        }
    }

    private void validateTracesInPhoenix() throws Exception {
        // Retrieve and validate traces
        List<String> spanNames = retrieveSpanNames();
        assertNotNull(spanNames, "Should be able to retrieve spans from Phoenix");
        assertFalse(spanNames.isEmpty(), "Should have at least one span");

        // Check for expected span types
        List<String> expectedSpans = List.of("agent", "llm", "tool");
        List<String> foundSpans = new ArrayList<>();

        for (String expectedSpan : expectedSpans) {
            if (spanNames.contains(expectedSpan)) {
                foundSpans.add(expectedSpan);
            }
        }

        assertFalse(foundSpans.isEmpty(),
                String.format("Should find at least one expected span. Expected: %s, Found: %s, All spans: %s",
                        expectedSpans, foundSpans, spanNames));
    }

    private void assertPhoenixIsRunning() throws Exception {
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(PHOENIX_HEALTH_ENDPOINT))
                .timeout(Duration.ofSeconds(5))
                .build();

        HttpResponse<String> response = HTTP_CLIENT.send(request, HttpResponse.BodyHandlers.ofString());
        assertEquals(response.statusCode(), 200, "Phoenix collector should be running");
    }

    private List<String> retrieveSpanNames() throws Exception {
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(PHOENIX_SPANS_ENDPOINT))
                .header("accept", "application/json")
                .timeout(Duration.ofSeconds(10))
                .build();

        HttpResponse<String> response = HTTP_CLIENT.send(request, HttpResponse.BodyHandlers.ofString());
        assertEquals(response.statusCode(), 200, "Should successfully retrieve spans from Phoenix");

        JsonNode rootNode = OBJECT_MAPPER.readTree(response.body());
        List<String> spanNames = new ArrayList<>();

        // Handle different response formats
        JsonNode spansNode = null;
        if (rootNode.has("spans")) {
            spansNode = rootNode.get("spans");
        } else if (rootNode.has("data")) {
            spansNode = rootNode.get("data");
        } else if (rootNode.has("items")) {
            spansNode = rootNode.get("items");
        } else if (rootNode.isArray()) {
            spansNode = rootNode;
        }

        if (spansNode != null && spansNode.isArray()) {
            for (JsonNode span : spansNode) {
                if (span.has("name")) {
                    spanNames.add(span.get("name").asText());
                } else if (span.has("span_name")) {
                    spanNames.add(span.get("span_name").asText());
                }
            }
        }

        return spanNames;
    }
}
