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

public class LLMSpan extends Span {

    private final String modelName;
    private final String providerName;
    private int inputIndex = 0;
    private int outputIndex = 0;

    public LLMSpan(String name, String modelName, String providerName) {
        super(name);
        this.modelName = modelName;
        this.providerName = providerName;
    }

    @Override
    public void init(String traceVar) {
        String code = """
                from opentelemetry import trace
                from openinference.semconv.trace import SpanAttributes
                %s = %s.start_as_current_span(
                        "%s",
                    attributes={
                        SpanAttributes.OPENINFERENCE_SPAN_KIND: "%s",
                            SpanAttributes.LLM_MODEL_NAME: "%s",
                        SpanAttributes.LLM_PROVIDER: "%s"
                    }
                )
                """.formatted(spanContextVar(), traceVar, name, SpanKind.LLM.toString(), modelName, providerName);
        PythonWrapper.execVoid(code);
    }

    @Override
    public void setInput(String input) {
        super.setInput(input);
        setAttribute("llm.input_messages.%d.message.role".formatted(inputIndex), "user");
        setAttribute("llm.input_messages.%d.message.content".formatted(inputIndex), input);
        inputIndex++;
    }

    @SuppressWarnings("unused")
    public void addToolCallInputs(ToolRequest... toolCalls) {
        String prefix = "llm.input_messages.%d.message.tool_calls".formatted(inputIndex);
        for (int i = 0; i < toolCalls.length; i++) {
            String perCallPrefix = "%s.%d.tool_call".formatted(prefix, i);
            System.out.println(toolCalls[i]);
            setJsonAttribute("%s.function.arguments".formatted(perCallPrefix), toolCalls[i].argumentJson);
            setAttribute("%s.function.name".formatted(perCallPrefix), toolCalls[i].name);
            setAttribute("%s.id".formatted(perCallPrefix), toolCalls[i].id);
        }
        setAttribute("llm.input_messages.%d.message.role".formatted(inputIndex), "assistant");
        inputIndex++;
    }

    @SuppressWarnings("unused")
    public void addToolCallResponse(ToolResponse toolResponse) {
        String prefix = "llm.input_messages.%d.message".formatted(inputIndex);
        setAttribute("%s.content".formatted(prefix), toolResponse.content);
        setAttribute("%s.name".formatted(prefix), toolResponse.name);
        setAttribute("%s.tool_call_id".formatted(prefix), toolResponse.id);
        setAttribute("%s.role".formatted(prefix), "tool");
        inputIndex++;
    }

    @SuppressWarnings("unused")
    public void addIntermediateResponse(String content) {
        String prefix = "llm.input_messages.%d.message".formatted(inputIndex);
        setAttribute("%s.content".formatted(prefix), content);
        setAttribute("%s.role".formatted(prefix), "assistant");
        inputIndex++;
    }

    @SuppressWarnings("unused")
    public void addIntermediateRequest(String content) {
        String prefix = "llm.input_messages.%d.message".formatted(inputIndex);
        setAttribute("%s.content".formatted(prefix), content);
        setAttribute("%s.role".formatted(prefix), "user");
        inputIndex++;
    }

    @Override
    public void setOutput(String output) {
        super.setOutput(output);
        setAttribute("llm.output_messages.%d.message.role".formatted(outputIndex), "assistant");
        setAttribute("llm.output_messages.%d.message.content".formatted(outputIndex), output);
        outputIndex++;
    }

    @SuppressWarnings("unused")
    public void setTokenCount(int total, int prompt, int completion) {
        setAttribute("llm.token_count.total", total);
        setAttribute("llm.token_count.prompt", prompt);
        setAttribute("llm.token_count.completion", completion);
    }

    public record ToolRequest(String name, String argumentJson, String id) {

    }

    public record ToolResponse(String name, String content, String id) {

    }
}
