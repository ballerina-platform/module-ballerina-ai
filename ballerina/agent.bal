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

# Represents the system prompt given to the agent.
@display {label: "System Prompt"}
public type SystemPrompt record {|

    # The role or responsibility assigned to the agent
    @display {label: "Role"}
    string role;

    # Specific instructions for the agent
    @display {label: "Instructions"}
    string instructions;
|};

# Represents the different types of agents supported by the module.
@display {label: "Agent Type"}
public enum AgentType {
    # Represents a ReAct agent
    REACT_AGENT,
    # Represents a function call agent
    FUNCTION_CALL_AGENT
}

# Provides a set of configurations for the agent.
@display {label: "Agent Configuration"}
public type AgentConfiguration record {|

    # The system prompt assigned to the agent
    @display {label: "System Prompt"}
    SystemPrompt systemPrompt;

    # The model used by the agent
    @display {label: "Model"}
    ModelProvider model;

    # The tools available for the agent
    @display {label: "Tools"}
    (BaseToolKit|ToolConfig|FunctionTool)[] tools = [];

    # Type of the agent
    @display {label: "Agent Type"}
    AgentType agentType = FUNCTION_CALL_AGENT;

    # The maximum number of iterations the agent performs to complete the task
    @display {label: "Maximum Iterations"}
    int maxIter = 5;

    # Specifies whether verbose logging is enabled
    @display {label: "Verbose"}
    boolean verbose = false;

    # The memory used by the agent to store and manage conversation history
    @display {label: "Memory"}
    Memory? memory = new MessageWindowChatMemory();
|};

# Represents an agent.
public isolated distinct client class Agent {
    private final BaseAgent agent;
    private final int maxIter;
    private final readonly & SystemPrompt systemPrompt;
    private final boolean verbose;

    # Initialize an Agent.
    #
    # + config - Configuration used to initialize an agent
    public isolated function init(@display {label: "Agent Configuration"} *AgentConfiguration config) returns Error? {
        self.maxIter = config.maxIter;
        self.verbose = config.verbose;
        self.systemPrompt = config.systemPrompt.cloneReadOnly();
        self.agent = config.agentType is REACT_AGENT ? check new ReActAgent(config.model, config.tools, config.memory)
            : check new FunctionCallAgent(config.model, config.tools, config.memory);
    }

    # Executes the agent for a given user query.
    #
    # + query - The natural language input provided to the agent
    # + sessionId - The ID associated with the agent memory
    # + return - The agent's response or an error
    isolated remote function run(@display {label: "Query"} string query, @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID) returns string|Error {
        var result = self.agent->run(query, self.maxIter, getFomatedSystemPrompt(self.systemPrompt), self.verbose, sessionId);
        string? answer = result.answer;
        if answer is string {
            return answer;
        }
        return constructError(result.steps, self.maxIter);
    }
}

isolated function constructError((ExecutionResult|ExecutionError)[] steps, int maxIter) returns Error {
    if (steps.length() == maxIter) {
        return error MaxIterationExceededError("Maximum iteration limit exceeded while processing the query.",
            steps = steps);
    }
    // Validates whether the execution steps contain only one memory error.
    // If there is exactly one memory error, it is returned; otherwise, null is returned.
    if steps.length() == 1 {
        ExecutionResult|ExecutionError step = steps.pop();
        if step is ExecutionError && step.'error is MemoryError {
            return <MemoryError>step.'error;
        }
    }
    return error Error("Unable to obtain valid answer from the agent", steps = steps);
}

isolated function getFomatedSystemPrompt(SystemPrompt systemPrompt) returns string {
    return string `# Role  
${systemPrompt.role}  

# Instructions  
${systemPrompt.instructions}`;
}
