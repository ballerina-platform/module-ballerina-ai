import ballerina/io;
import ballerina/jballerina.java;
import ballerina/lang.regexp;
import ballerina/lang.runtime;
import ballerina/time;

type SearchParams record {|
    string query;
|};

type CalculatorParams record {|
    string expression;
|};

type MessageRequest record {|
    string[] to;
    string subject;
    string body;
|};

// create two mock tools 
isolated function searchToolMock(*SearchParams params) returns string {
    string query = params.query.trim().toLowerAscii();
    if regexp:isFullMatch(re `.*girlfriend.*`, query) {
        return "Camila Morrone";

    } else if regexp:isFullMatch(re `.*age.*`, query) {
        return "25 years";
    }
    else {
        return "Can't find. Stop!";
    }
}

isolated function calculatorToolMock(*CalculatorParams params) returns string {
    string expression = params.expression.trim();
    if (expression == "25 ^ 0.43") {
        return "Answer: 3.991298452658078";
    } else {
        return "Can't compute. Some information is missing";
    }
}

// Records the execution time window of each slow mock tool, keyed by tool name, so that tests
// can assert whether tool executions overlapped (parallel) or not (sequential).
isolated map<[decimal, decimal]> toolExecutionWindows = {};

isolated function recordToolExecutionWindow(string toolName, decimal startTime, decimal endTime) {
    lock {
        toolExecutionWindows[toolName] = [startTime, endTime];
    }
}

isolated function getToolExecutionWindow(string toolName) returns [decimal, decimal]|error {
    lock {
        if !toolExecutionWindows.hasKey(toolName) {
            return error(string `Execution window not recorded for ${toolName} tool`);
        }
        return toolExecutionWindows.get(toolName).clone();
    }
}

// Slow variants of the mock tools that sleep before responding and record their
// execution time windows, used to verify parallel vs sequential tool execution.
isolated function slowSearchToolMock(*SearchParams params) returns string {
    decimal startTime = time:monotonicNow();
    runtime:sleep(1);
    recordToolExecutionWindow("Search", startTime, time:monotonicNow());
    return "Camila Morrone";
}

isolated function slowCalculatorToolMock(*CalculatorParams params) returns string {
    decimal startTime = time:monotonicNow();
    runtime:sleep(1);
    recordToolExecutionWindow("Calculator", startTime, time:monotonicNow());
    return "Answer: 3.991298452658078";
}

isolated function sendMail(record {|string senderEmail; MessageRequest messageRequest;|} 'input) returns string|error {
    if 'input.senderEmail == "test@email.com" {
        return error("Invalid sender email");
    } else {
        return "Mail sent successfully";
    }
}

public isolated client class MockLLM {
    *ModelProvider;

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools, string? stop)
        returns ChatAssistantMessage|LlmError {
        ChatMessage lastMessage = messages is ChatUserMessage ? messages : messages.pop();
        string prompt = lastMessage is ChatUserMessage ? getChatMessageStringContent(lastMessage.content) : "";
        if prompt.includes("Who is Leo DiCaprio's girlfriend? What is her current age raised to the 0.43 power?") {
            int queryLevel = regexp:findAll(re `observation`, prompt.toLowerAscii()).length();
            io:println(queryLevel, prompt);
            string content = check getChatAssistantMessageContent(queryLevel);
            return {role: ASSISTANT, content};
        }
        return error LlmError("Unexpected prompt to MockLLM");
    }

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.lib.ai.MockGenerator"
    } external;
}

// Responds based on the current turn's query, so a multi-turn conversation can be scripted:
// - "first turn query" and "third turn query" get a normal final answer.
// - "second turn query" gets a response with neither a tool call nor chat content, which the
//   agent cannot parse into either a `FunctionCall` or a final answer.
public isolated client class ScriptedMockLLM {
    *ModelProvider;

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [],
            string? stop = ()) returns ChatAssistantMessage|Error {
        ChatMessage lastMessage = messages is ChatUserMessage ? messages : messages[messages.length() - 1];
        string prompt = lastMessage is ChatUserMessage ? getChatMessageStringContent(lastMessage.content) : "";
        if prompt.includes("first turn query") {
            return {role: ASSISTANT, content: "first turn answer"};
        }
        if prompt.includes("second turn query") {
            return {role: ASSISTANT};
        }
        if prompt.includes("third turn query") {
            return {role: ASSISTANT, content: "third turn answer"};
        }
        return error Error("Unexpected prompt to ScriptedMockLLM: " + prompt);
    }

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error = external;
}

// Returns both the `Search` and `Calculator` tool calls together in a single response, then, once
// both tool results are present in the conversation history, returns the final answer.
// Used to verify that multiple tool calls returned in one LLM response are all executed before the
// LLM is consulted again, instead of one round-trip per tool call.
public isolated client class MultiToolCallMockLLM {
    *ModelProvider;

    private int chatCallCount = 0;

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [],
            string? stop = ()) returns ChatAssistantMessage|Error {
        lock {
            self.chatCallCount += 1;
        }
        int toolResultCount = messages is ChatUserMessage ? 0
            : messages.filter(msg => msg is ChatFunctionMessage).length();
        if toolResultCount == 0 {
            return {
                role: ASSISTANT,
                toolCalls: [
                    {name: "Search", arguments: {params: {query: "Leo DiCaprio girlfriend"}}, id: "call-1"},
                    {name: "Calculator", arguments: {params: {expression: "25 ^ 0.43"}}, id: "call-2"}
                ]
            };
        }
        if toolResultCount == 2 {
            return {
                role: ASSISTANT,
                content: "Leo DiCaprio's girlfriend is Camila Morrone, and 25 raised to the power of 0.43 is " +
                    "Answer: 3.991298452658078"
            };
        }
        return error Error("Unexpected number of tool results in history: " + toolResultCount.toString());
    }

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error = external;

    # Returns the number of times the LLM was consulted, so that tests can assert
    # all the tool calls from one response were executed without extra round-trips.
    #
    # + return - The number of times `chat` has been called
    public isolated function getChatCallCount() returns int {
        lock {
            return self.chatCallCount;
        }
    }
}

isolated function getChatAssistantMessageContent(int queryLevel) returns string|LlmError {
    match queryLevel {
        3 => {
            return "I should use a search engine to find out who Leo DiCaprio's girlfriend is, and then use a calculator to calculate her current age raised to the 0.43 power." +
                "Action:" +
                "```" +
                "{" +
                    "\"action\": \"Search\"," +
                    "\"action_input\": {" +
                        "\"params\": {" +
                            "\"query\": \"Leo DiCaprio girlfriend\"" +
                        "}" +
                    "}" +
                "}" +
                "```";
        }
        4 => {
            return " I need to find out Camila Morrone's age" +
                "Action:" +
                "```" +
                "{" +
                    "\"action\": \"Search\"," +
                    "\"action_input\": {" +
                        "\"params\": {" +
                            "\"query\": \"Camila Morrone age\"" +
                        "}" +
                    "}" +
                "}" +
                "```";

        }
        5 => {
            {
                return " I now need to calculate the age raised to the 0.43 power" +
                "Action:" +
                "```" +
                "{" +
                    "\"action\": \"Calculator\"," +
                    "\"action_input\": {" +
                        "\"params\": {" +
                            "\"expression\": \"25 ^ 0.43\"" +
                        "}" +
                    "}" +
                "}" +
                "```";
            }
        }
    }
    return error LlmError("Unexpected prompt to MockLLM");
}

isolated function testTool(string a, string b = "default-one", string c = "default-two") returns string {
    return string `${a} ${b} ${c}`;
}

isolated function testToolPanic(string data) returns string {
    error e = error(data);
    panic (e);
}
