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
