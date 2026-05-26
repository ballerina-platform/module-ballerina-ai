import ballerina/ai;

type Address record {|
    string city;
    string country;
|};

type Person record {|
    string name;
    int age;
    Address address;
|};

type Company record {|
    string name;
|};

// Union return type: the `ai:Agent.run` result type is a union, so the plugin must walk each member and
// generate a schema for every `anydata` record member (skipping the `ai:Error` member).
isolated function getEither(ai:Agent agent) returns Person|Company|ai:Error => agent.run("Give me a person or company.");

// Array return type: the plugin must descend into the array member type and generate `Person`'s schema.
isolated function getPeople(ai:Agent agent) returns Person[]|ai:Error => agent.run("Give me people.");

// Inline (anonymous) record return type: the plugin must walk the record's field types directly.
isolated function getInline(ai:Agent agent) returns record {|string title; int year;|}|ai:Error =>
    agent.run("Give me a book.");

// Tuple return type: the plugin must walk each tuple member type.
isolated function getTuple(ai:Agent agent) returns [Person, int]|ai:Error => agent.run("Give me a person and a count.");
