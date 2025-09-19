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

package io.ballerina.stdlib.ai.observability;

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

        insertTraces();

        // Wait for traces to be exported
        TimeUnit.SECONDS.sleep(5);

        // Finally validate traces using pure Java
        validateTracesInPhoenix();
    }

    private void insertTraces() {
        Observability.initTracing(PHOENIX_BASE_URL + "/v1/traces", "TT");
        AgentSpan agentSpan = new AgentSpan("agent");
        agentSpan.init(Observability.TRACER);
        agentSpan.enter();
        agentSpan.setInput("h1");

        {
            LLMSpan llmSpan = new LLMSpan("llm", "chatgpt-4o-latest", "openai");
            llmSpan.init(Observability.TRACER);
            llmSpan.enter();
            llmSpan.setInput("hi llm");
            String toolInput = """
                    {
                        "arg1": "value1",
                        "arg2": "value2"
                    }
                    """;
            llmSpan.addToolCallInputs(new LLMSpan.ToolRequest("tool-name", toolInput, "12345"));
            {
                ToolSpan toolSpan = new ToolSpan("tool");
                toolSpan.init(Observability.TRACER);
                toolSpan.enter();
                toolSpan.setInput(toolInput);
                toolSpan.setOutput("tool output");
                toolSpan.setStatus(Span.Status.OK);
                toolSpan.exit();
            }
            llmSpan.addToolCallResponse(new LLMSpan.ToolResponse("tool-name", "tool output", "12345"));

            llmSpan.addIntermediateRequest("what is the output of the tool?");
            llmSpan.addIntermediateResponse("the output of the tool is great");

            llmSpan.setOutput("final llm output");
            llmSpan.setTokenCount(150, 100, 50);
            llmSpan.setStatus(Span.Status.OK);
            llmSpan.exit();
        }

        agentSpan.setOutput("end of agent");
        agentSpan.setStatus(Span.Status.OK);
        agentSpan.exit();
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
