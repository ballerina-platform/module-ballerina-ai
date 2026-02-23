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

import ballerina/time;

# Represents the trace of an agent's execution.
public type Trace record {|
    # Unique identifier for the trace
    string id;
    # Input message provided by the user
    ChatUserMessage userMessage;
    # Sequence of iterations performed by the agent
    Iteration[] iterations;
    # Final output produced by the agent
    ChatAssistantMessage|Error output;
    # Tool invocations requested by the LLM in this turn
    FunctionCall[] toolCalls?;
    # Schema of the tools used by the agent during execution
    ToolSchema[] tools;
    # Start time of the trace
    time:Utc startTime;
    # End time of the trace
    time:Utc endTime;
|};

# Represents the schema of a tool used by the agent.
public type ToolSchema record {|
    # Name of the tool
    string name;
    # Description of the tool
    string description;
    # Parameters schema of the tool
    map<json> parametersSchema?;
|};

# Represents a single execution step of an agent iteration.
public type Iteration record {|
    # History of chat messages up to this iteration
    ChatMessage[] history;
    # Output produced by the agent in this iteration
    ChatAssistantMessage|ChatFunctionMessage|Error output;
    # Start time of the iteration
    time:Utc startTime;
    # End time of the iteration
    time:Utc endTime;
|};
