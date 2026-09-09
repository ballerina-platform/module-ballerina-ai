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

// Implementing `ai:FixedTypedAgent` with a non-`anydata` return type (`stream<int>`) from `run` must
// be a compile-time error, since the contract fixes the return type to `anydata|ai:Error`.
isolated class BadAgent {
    *ai:FixedTypedAgent;

    public isolated function run(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns stream<int>|ai:Error => (<int[]>[]).toStream();

    public isolated function trace(string|ai:Prompt query, string sessionId = "default-session",
            ai:Context context = new) returns ai:Trace|ai:Error => error("not implemented");
}
