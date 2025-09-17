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

import org.graalvm.polyglot.Context;
import org.graalvm.python.embedding.GraalPyResources;
import org.testng.annotations.Test;

public class TracingTest {

    @Test
    public void testGraalpy() {
        String code = """
                import os
                from opentelemetry import trace
                from opentelemetry.sdk.trace import TracerProvider
                from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter
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
                    auto_instrument=True, # See 'Trace all calls made to a library' below
                    endpoint="http://localhost:6006/v1/traces",
                )
                
                tracer = tracer_provider.get_tracer(__name__)
                
                def chat(prompt: str) -> str:
                    span_context = tracer.start_as_current_span(
                        "llm",
                        attributes={
                            GEN_AI_PROVIDER_NAME: "openai",  # e.g., the provider
                            GEN_AI_REQUEST_MODEL: "gpt-4",   # specify your model
                            GEN_AI_USAGE_INPUT_TOKENS: 100, # optional: token count
                            GEN_AI_USAGE_OUTPUT_TOKENS: 50, # optional: token count
                        },
                        kind=trace.SpanKind.CLIENT,  # Use CLIENT span kind for LLM calls
                    )
                    span = span_context.__enter__()
                    try:
                        # Set input value (required for OpenInference LLM span).
                        span.set_attribute("input.value", prompt)
                
                        # Simulate the actual LLM call here (replace with your real API call).
                        # For example: response = openai.ChatCompletion.create(...)
                        response = f"LLM response to: {prompt}"
                
                        # Set output value (required for OpenInference LLM span).
                        span.set_attribute("output.value", response)
                
                        # Optional: Add events for intermediate steps if needed.
                        # span.add_event("generation.completed", attributes={"reason": "done"})
                
                        return response
                    finally:
                        span_context.__exit__(None, None, None)
                
                def tool(input_str: str) -> str:
                    span_context = tracer.start_as_current_span(
                        "tool",
                        attributes={
                            GEN_AI_TOOL_NAME: "example_tool",  # name of the tool
                        },
                        kind=trace.SpanKind.INTERNAL,  # Tools are typically INTERNAL
                    )
                    span = span_context.__enter__()
                    try:
                        # Set input value (required for OpenInference TOOL span).
                        span.set_attribute("input.value", input_str)
                
                        # Simulate the actual tool execution here (replace with your logic).
                        # For example: result = some_function(input_str)
                        result = f"Tool result for: {input_str}"
                
                        # Set output value (required for OpenInference TOOL span).
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
                        # Set initial input for the agent.
                        span.set_attribute("input.value", initial_prompt)
                
                        # Simulate agent loop: chat -> decide tool -> tool -> chat again.
                        current_state = initial_prompt
                
                        # First chat call.
                        current_state = chat(current_state)
                
                        # Simulate agent decides to call a tool based on chat output.
                        tool_input = "extract info from: " + current_state  # In real agent, parse from chat response.
                        current_state = tool(tool_input)
                
                        # Second chat call with tool result.
                        final_response = chat(current_state)
                
                        # Set overall output for the agent span.
                        span.set_attribute("output.value", final_response)
                
                        return final_response
                    finally:
                        span_context.__exit__(None, None, None)
                
                agent_flow("Hi how are you?")
                """;

        try (Context cx = GraalPyResources.createContext()) {
            cx.eval("python", code);
        }
    }
}
