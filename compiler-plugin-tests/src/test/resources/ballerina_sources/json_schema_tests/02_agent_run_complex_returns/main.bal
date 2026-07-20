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
