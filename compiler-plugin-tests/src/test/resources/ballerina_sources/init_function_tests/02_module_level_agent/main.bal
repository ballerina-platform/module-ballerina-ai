import ballerina/ai;

final ai:Agent supportAgent = check new (
    systemPrompt = {role: "Support Agent", instructions: "Help users."},
    model = check ai:getDefaultModelProvider(),
    tools = []
);
