import ballerina/ai;

# An agent defined as a class, with no module-level agent declaration anywhere in the module.
public isolated class SupportAgent {
    *ai:FixedTypedAgent;

    private final ai:Agent agent;

    public function init(ai:ModelProvider model) returns error? {
        self.agent = check new (
            systemPrompt = {role: "Support Agent", instructions: "Help users."}, model = model, tools = []
        );
    }

    public isolated function run(string|ai:Prompt query, string sessionId = "sessionId",
            ai:Context context = new) returns string|ai:Error {
        return self.agent.run(query, sessionId, context);
    }

    public isolated function trace(string|ai:Prompt query, string sessionId = "sessionId",
            ai:Context context = new) returns ai:Trace|ai:Error {
        return self.agent.run(query, sessionId, context);
    }
}
