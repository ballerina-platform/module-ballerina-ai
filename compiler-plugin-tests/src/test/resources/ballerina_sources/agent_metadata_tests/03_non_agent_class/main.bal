// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
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

@ai:AgentTool
isolated function lookupOrder(string orderId) returns string => "order found";

// Composes an `ai:Agent`, but does NOT include `*ai:FixedTypedAgent` (or
// `*ai:DependentlyTypedAgent`), so it is not a custom agent definition and no
// agent metadata annotation should be attached.
public isolated class OrderHelper {

    private final ai:Agent agent;

    public function init(ai:ModelProvider model) returns error? {
        self.agent = check new (
            systemPrompt = {role: "Order Helper", instructions: "Help with orders."},
            model = model,
            tools = [lookupOrder]
        );
    }

    public isolated function ask(string query) returns string|ai:Error => self.agent.run(query);
}
