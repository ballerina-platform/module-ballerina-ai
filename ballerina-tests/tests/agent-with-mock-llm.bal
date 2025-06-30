// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/ai;
import ballerina/jballerina.java;
import ballerina/lang.regexp;

isolated function getNumbers(string prompt) returns string[] {
    regexp:Span[] spans = re `-?\d+\.?\d*`.findAll(prompt);
    return spans.'map(span => span.substring());
}

isolated function getAnswer(string prompt) returns string {
    var result = re `.*(Answer is: .*)\n?`.findGroups(prompt);
    if result is () || result.length() <= 1 {
        return "Sorry! I don't know the answer";
    }
    var answer = result[1];
    return answer is () ? "Sorry! I don't know the answer" : answer.substring();
}

isolated function getDecimals(string[] numbers) returns decimal[] {
    decimal[] decimalVals = [];
    foreach var num in numbers {
        decimal|error decimalVal = decimal:fromString(num);
        decimalVals.push(decimalVal is decimal ? decimalVal : 0d);
    }
    return decimalVals;
}

isolated function getInt(string number) returns int {
    int|error intVal = int:fromString(number);
    return intVal is int ? intVal : 0;
}

type MockLlmToolCall record {|
    string action;
    json action_input;
|};

@ai:AgentTool
isolated function sum(decimal[] numbers) returns string {
    decimal total = 0;
    foreach decimal number in numbers {
        total += number;
    }
    return string `Answer is: ${total}`;
}

@ai:AgentTool
isolated function mutiply(int a, int b) returns string {
    return string `Answer is: ${a * b}`;
}

@ai:AgentTool
isolated function getEmails() returns stream<Mail, ai:Error?>|error? {
    return [{body: "Mail Body 1"}, {body: "Mail Body 2"}, {body: "Mail Body 3"}].toStream();
}

isolated client distinct class MockLlm {
    *ai:ModelProvider;

    isolated remote function chat(ai:ChatMessage[]|ai:ChatUserMessage messages, ai:ChatCompletionFunctions[] tools, string? stop)
        returns ai:ChatAssistantMessage|ai:LlmError {
        ai:ChatMessage lastMessage = messages is ai:ChatUserMessage ? messages : messages.pop();
        if lastMessage !is ai:ChatUserMessage|ai:ChatFunctionMessage {
            return error ai:LlmError("I can't understand");
        }
        ai:Prompt|string? lasMessageContent = lastMessage.content;
        string query = getChatMessageStringContent(lasMessageContent ?: "");
        if query.includes("Greet") {
            return {role: ai:ASSISTANT, content: "Hey John! Welcome to Ballerina!"};
        }
        if query.includes("Mail Body") {
            return {role: ai:ASSISTANT, content: query};
        }
        if query.includes("Answer is:") {
            return {role: ai:ASSISTANT, content: getAnswer(query)};
        }
        if query.toLowerAscii().includes("mail") {
            ai:FunctionCall functionCall = {name: "getEmails"};
            return {role: ai:ASSISTANT, toolCalls: [functionCall]};
        }
        if query.toLowerAscii().includes("search") {
            regexp:Span? span = re `'.*'`.find(query);
            string searchQuery = span is () ? "No search query" : span.substring();
            ai:FunctionCall functionCall = {name: "searchDoc", arguments: {searchQuery}};
            return {role: ai:ASSISTANT, toolCalls: [functionCall]};
        }
        if query.toLowerAscii().includes("sum") || query.toLowerAscii().includes("add") {
            decimal[] numbers = getDecimals(getNumbers(query));
            ai:FunctionCall functionCall = {name: "sum", arguments: {numbers}};
            return {role: ai:ASSISTANT, toolCalls: [functionCall]};
        }
        if query.toLowerAscii().includes("mult") || query.toLowerAscii().includes("prod") {
            string[] numbers = getNumbers(query);
            int a = getInt(numbers.shift());
            int b = getInt(numbers.shift());
            ai:FunctionCall functionCall = {name: "mutiply", arguments: {a, b}};
            return {role: ai:ASSISTANT, toolCalls: [functionCall]};
        }
        return error ai:LlmError("I can't understand");
    }

    public isolated function generate(ai:Prompt prompt, typedesc<anydata> td = <>) returns td|ai:Error = @java:Method {
        'class: "io.ballerina.lib.ai.MockGenerator"
    } external;
}

isolated function getChatMessageStringContent(ai:Prompt|string prompt) returns string {
    if prompt is string {
        return prompt;
    }
    string str = prompt.strings[0];
    anydata[] insertions = prompt.insertions;
    foreach int i in 0 ..< insertions.length() {
        anydata value = insertions[i];
        string promptStr = prompt.strings[i + 1];
        if value is ai:TextDocument|ai:TextChunk {
            str = str + value.content + promptStr;
            continue;
        }
        str = str + value.toString() + promptStr;
    }
    return str.trim();
}

final MockLlm model = new;
final ai:Agent agent = check new (model = model,
    systemPrompt = {role: "Math tutor", instructions: "Help the students with their questions."},
    tools = [sum, mutiply, new SearchToolKit(), getEmails]
);

isolated class SearchToolKit {
    *ai:BaseToolKit;

    public isolated function getTools() returns ai:ToolConfig[] {
        return ai:getToolConfigs([self.searchDoc]);
    }

    @ai:AgentTool
    public isolated function searchDoc(string searchQuery) returns string {
        return string `Answer is: No result found on doc for ${searchQuery}`;
    }
}
