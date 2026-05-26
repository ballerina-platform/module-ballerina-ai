import ballerina/ai;

type Person record {|
    string name;
|};

// A custom object that happens to expose a `run` method but is NOT an `ai:Agent`.
isolated class NotAnAgent {
    isolated function run(string query) returns Person => {name: query};
}

// Exercises the two negative branches of the agent-run detection:
//   1. A method call whose name is not run (e.g. string.trim()) must be ignored.
//   2. A run call on an expression that is not a subtype of ai:Agent must be ignored, so no schema
//      annotation is generated for Person here.
isolated function useNonAgent() returns Person {
    string _ = "  hello  ".trim();
    NotAnAgent other = new;
    return other.run("alice");
}
