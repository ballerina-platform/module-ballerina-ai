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

package io.ballerina.stdlib.ai.unified;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
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
import static org.testng.Assert.assertTrue;

/**
 * Test to validate that the unified platform-agnostic observability interface
 * works correctly by creating traces through the platform-specific implementations.
 */
public class UnifiedTracingTest {

    private static final String PHOENIX_BASE_URL = "http://localhost:6006";
    private static final String PHOENIX_SPANS_ENDPOINT = PHOENIX_BASE_URL + "/v1/projects/unified-test/spans?limit=100";
    private static final String PHOENIX_HEALTH_ENDPOINT = PHOENIX_BASE_URL + "/healthz";
    private static final HttpClient HTTP_CLIENT = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    @Test
    public void testUnifiedTracingIntegration() throws Exception {
        // First, verify platform detection works
        System.out.println("Platform info: " + PlatformObservabilityManager.getPlatformInfo());
        assertTrue(PlatformObservabilityManager.isAvailable(),
            "Platform-specific observability should be available. Error: " +
            PlatformObservabilityManager.getInitializationError().map(Exception::getMessage).orElse("None"));

        // Check if Phoenix is running
        assertPhoenixIsRunning();

        // Execute traces using unified interface
        insertTracesViaUnifiedInterface();

        // Wait for traces to be exported
        TimeUnit.SECONDS.sleep(5);

        // Validate traces were created
        validateTracesInPhoenix();
    }

    private void insertTracesViaUnifiedInterface() {
        System.out.println("Initializing tracing via unified interface...");
        PlatformObservabilityManager.initTracing(PHOENIX_BASE_URL + "/v1/traces", "unified-test");

        String tracer = PlatformObservabilityManager.getTracer();
        System.out.println("Using tracer: " + tracer);

        System.out.println("Creating agent span...");
        UnifiedAgentSpan agentSpan = new UnifiedAgentSpan("unified-agent");
        agentSpan.init(tracer);
        agentSpan.enter();
        agentSpan.setInput("unified test input");

        {
            System.out.println("Creating LLM span...");
            UnifiedLLMSpan llmSpan = new UnifiedLLMSpan("unified-llm", "gpt-4", "openai");
            llmSpan.init(tracer);
            llmSpan.enter();
            llmSpan.setInput("unified llm input");

            String toolInput = """
                    {
                        "unified_arg1": "unified_value1",
                        "unified_arg2": "unified_value2"
                    }
                    """;
            llmSpan.addToolCallInputs(new UnifiedLLMSpan.ToolRequest("unified-tool", toolInput, "unified-12345"));

            {
                System.out.println("Creating tool span...");
                UnifiedToolSpan toolSpan = new UnifiedToolSpan("unified-tool");
                toolSpan.init(tracer);
                toolSpan.enter();
                toolSpan.setInput(toolInput);
                toolSpan.setOutput("unified tool output");
                toolSpan.setStatus(SpanStatus.OK);
                toolSpan.exit();
            }

            llmSpan.addToolCallResponse(new UnifiedLLMSpan.ToolResponse("unified-tool", "unified tool output", "unified-12345"));
            llmSpan.addIntermediateRequest("what is the unified output?");
            llmSpan.addIntermediateResponse("the unified output is excellent");
            llmSpan.setOutput("unified llm final output");
            llmSpan.setTokenCount(200, 120, 80);
            llmSpan.setStatus(SpanStatus.OK);
            llmSpan.exit();
        }

        agentSpan.setOutput("unified agent completed");
        agentSpan.setStatus(SpanStatus.OK);
        agentSpan.exit();

        System.out.println("Traces inserted successfully via unified interface!");
    }

    private void validateTracesInPhoenix() throws Exception {
        System.out.println("Validating traces in Phoenix...");

        // Retrieve and validate traces
        List<String> spanNames = retrieveSpanNames();
        assertNotNull(spanNames, "Should be able to retrieve spans from Phoenix");
        assertFalse(spanNames.isEmpty(), "Should have at least one span");

        System.out.println("Found spans: " + spanNames);

        // Check for expected span types (with unified prefix)
        List<String> expectedSpans = List.of("unified-agent", "unified-llm", "unified-tool");
        List<String> foundSpans = new ArrayList<>();

        for (String expectedSpan : expectedSpans) {
            if (spanNames.contains(expectedSpan)) {
                foundSpans.add(expectedSpan);
            }
        }

        assertFalse(foundSpans.isEmpty(),
                String.format("Should find at least one expected unified span. Expected: %s, Found: %s, All spans: %s",
                        expectedSpans, foundSpans, spanNames));

        System.out.println("Successfully validated unified tracing! Found spans: " + foundSpans);
    }

    private void assertPhoenixIsRunning() throws Exception {
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(PHOENIX_HEALTH_ENDPOINT))
                .timeout(Duration.ofSeconds(5))
                .build();

        HttpResponse<String> response = HTTP_CLIENT.send(request, HttpResponse.BodyHandlers.ofString());
        assertEquals(response.statusCode(), 200, "Phoenix collector should be running");
        System.out.println("Phoenix is running and healthy");
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