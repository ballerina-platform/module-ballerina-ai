import ballerina/ai;

type Person record {|
    string name;
    int age;
|};

// The compiler plugin should generate an `@ai:JsonSchema` annotation for `Person`, since it is the
// inferred return type of an `ai:Agent.run` call.
isolated function getPerson(ai:Agent agent) returns Person|ai:Error => agent.run("Give me a person.");
