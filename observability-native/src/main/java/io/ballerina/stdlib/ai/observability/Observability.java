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

public class Observability {

    public static final String TRACER = "tracer";

    private Observability() {

    }

    public static void initTracing(String phoenixEndpoint, String projectName) {
        String code = """
                import os
                os.environ["PHOENIX_COLLECTOR_ENDPOINT"] = "%s"
                from phoenix.otel import register
                tracer_provider = register(
                  project_name="%s", # Default is 'default'
                  auto_instrument=True, # See 'Trace all calls made to a library' below
                  endpoint="%s",
                )
                %s = tracer_provider.get_tracer(__name__)
                """.formatted(phoenixEndpoint, projectName, phoenixEndpoint, TRACER);
        PythonWrapper.execVoid(code);
    }

    public static AgentSpan createAgentSpan(String name) {
      AgentSpan agentSpan = new AgentSpan("agent");
      agentSpan.init(Observability.TRACER);
      return agentSpan;
    }

    public static LLMSpan createLLMSpan(String name, String modelName, String providerName) {
      LLMSpan llmSpan = new LLMSpan(name, modelName, providerName);
      llmSpan.init(Observability.TRACER);
      return llmSpan;
    }

    public static void enterSpan(Span span) {
      span.enter();
    }

    public static void setInput(Span span, String input) {
      span.setInput(input);
    }

    public static void setOutput(Span span, String output) {
      span.setOutput(output);
    }

    public static void setStatus(Span span, String status) {
      span.setStatus(Span.Status.from(status));
    }
}
