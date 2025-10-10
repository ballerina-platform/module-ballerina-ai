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

public class AgentSpan extends Span {

    public AgentSpan(String name) {
        super(name);
    }

    @Override
    public void init(String traceVar) {
        String code = """
                from opentelemetry import trace
                from openinference.semconv.trace import SpanAttributes
                %s = %s.start_as_current_span(
                        "%s",
                    attributes={SpanAttributes.OPENINFERENCE_SPAN_KIND: "%s"}
                )
                """.formatted(spanContextVar(), traceVar, name, SpanKind.AGENT.toString());
        PythonWrapper.execVoid(code);
    }
}
