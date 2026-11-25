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

// A remote agent reached through an API gateway, the way agents are usually reached in production: the gateway
// wants a credential on every request, the Agent Card included, while the agent behind it declares no security
// scheme of its own. The gateway below forwards to the scripted agent and rewrites the card to point at itself.

import ballerina/http;
import ballerina/test;

const int A2A_GATEWAY_TEST_PORT = 19303;
const string A2A_GATEWAY_PREFIX = "/agents/scripted";
const string A2A_GATEWAY_API_KEY = "gateway-key";
const string A2A_GATEWAY_TOKEN = "gateway-token";
final string a2aGatewayUrl = string `http://localhost:${A2A_GATEWAY_TEST_PORT}${A2A_GATEWAY_PREFIX}`;

final http:Client a2aGatewayUpstream = check new (a2aScriptedAgentUrl);
isolated string[] a2aGatewaySeen = [];

listener http:Listener a2aGatewayListener = new (A2A_GATEWAY_TEST_PORT);

// A path segment with a colon only matches a resource that names it, so the A2A operations the tests use are listed.
service /agents/scripted on a2aGatewayListener {
    isolated resource function post message\:stream(http:Request req) returns http:Response|error => a2aGatewayForward(req);

    isolated resource function post message\:send(http:Request req) returns http:Response|error => a2aGatewayForward(req);

    isolated resource function 'default [string... path](http:Request req) returns http:Response|error =>
        a2aGatewayForward(req);
}

isolated function a2aGatewayForward(http:Request req) returns http:Response|error {
    string target = req.rawPath.substring(A2A_GATEWAY_PREFIX.length());
    string|http:HeaderNotFoundError apiKey = req.getHeader("X-API-Key");
    string|http:HeaderNotFoundError authorization = req.getHeader("Authorization");
    boolean allowed = apiKey == A2A_GATEWAY_API_KEY || authorization == string `Bearer ${A2A_GATEWAY_TOKEN}`;
    lock {
        a2aGatewaySeen.push(string `${req.method} ${target} ${allowed ? "allowed" : "refused"}`);
    }
    if !allowed {
        http:Response refused = new;
        refused.statusCode = 401;
        refused.setHeader("WWW-Authenticate", "Bearer");
        return refused;
    }
    req.removeHeader("X-API-Key");
    req.removeHeader("Authorization");
    // The card is served at the agent's root; the operations are mounted under /rest.
    boolean isCard = target.startsWith("/.well-known/agent-card.json");
    http:Response response = check a2aGatewayUpstream->execute(req.method, isCard ? target : "/rest" + target, req);
    if isCard {
        map<json> card = check (check response.getJsonPayload()).ensureType();
        json[] interfaces = check card["supportedInterfaces"].ensureType();
        foreach json iface in interfaces {
            map<json> entry = check iface.ensureType();
            entry["url"] = a2aGatewayUrl;
        }
        response.setJsonPayload(card);
    }
    return response;
}

isolated function a2aGatewayLog() returns string[] {
    lock {
        string[] seen = a2aGatewaySeen.clone();
        a2aGatewaySeen.removeAll();
        return seen.clone();
    }
}

@test:Config {groups: ["a2a"]}
function testA2aToolKitSendsItsHeadersToAGatewayOnEveryRequest() returns error? {
    _ = a2aGatewayLog();
    A2aToolKit toolkit = check new (a2aGatewayUrl, headers = {"X-API-Key": A2A_GATEWAY_API_KEY});
    Agent agent = check new (systemPrompt = {role: "Relay", instructions: "Pass every request on."},
        model = new A2aRelayMockLLM(), tools = [toolkit]);

    string reply = check agent.run("echo through the gateway", sessionId = "gw-key");
    test:assertEquals(reply, "through the gateway");
    string[] seen = a2aGatewayLog();
    test:assertTrue(seen.indexOf("GET /.well-known/agent-card.json allowed") is int, seen.toString());
    test:assertTrue(seen.indexOf("POST /message:stream allowed") is int, seen.toString());
    test:assertEquals(seen.filter(line => line.endsWith("refused")).length(), 0, seen.toString());
}

@test:Config {groups: ["a2a"]}
function testA2aToolKitSendsClientConfigAuthToAGatewayOnEveryRequest() returns error? {
    _ = a2aGatewayLog();
    A2aToolKit toolkit = check new (a2aGatewayUrl, clientConfig = {auth: {token: A2A_GATEWAY_TOKEN}});
    Agent agent = check new (systemPrompt = {role: "Relay", instructions: "Pass every request on."},
        model = new A2aRelayMockLLM(), tools = [toolkit]);

    // A question and its answer: the continuation goes through the gateway with the token too.
    string question = check agent.run("ask", sessionId = "gw-token");
    test:assertTrue(question.startsWith("[INPUT_REQUIRED] which one?"), question);
    string answer = check agent.run("the small one", sessionId = "gw-token");
    test:assertEquals(answer, "the small one");
    string[] seen = a2aGatewayLog();
    test:assertTrue(seen.indexOf("GET /.well-known/agent-card.json allowed") is int, seen.toString());
    test:assertEquals(seen.filter(line => line.endsWith("refused")).length(), 0, seen.toString());
}

@test:Config {groups: ["a2a"]}
function testA2aToolKitWithoutTheGatewayCredentialFailsClearly() {
    A2aToolKit|Error toolkit = new (a2aGatewayUrl);
    if toolkit is A2aToolKit {
        test:assertFail("the gateway refuses the card without a credential");
    }
    test:assertTrue(toolkit.message().startsWith(string `could not resolve the Agent Card for ${a2aGatewayUrl}`),
            toolkit.message());
}

@test:Config {groups: ["a2a"]}
function testA2aToolKitAcceptsTheAgentCardUrl() returns error? {
    A2aToolKit toolkit = check new (a2aGatewayUrl + "/.well-known/agent-card.json",
        headers = {"X-API-Key": A2A_GATEWAY_API_KEY});
    test:assertEquals(a2aOnlyTool(toolkit).name, "askScriptedAgent");
}

@test:Config {groups: ["a2a"]}
function testA2aAgentBaseUrlStripsOnlyTheCardPath() {
    test:assertEquals(agentBaseUrl("https://gw.example.com/agents/x/.well-known/agent-card.json"),
            "https://gw.example.com/agents/x");
    test:assertEquals(agentBaseUrl("https://gw.example.com/agents/x/"), "https://gw.example.com/agents/x");
    test:assertEquals(agentBaseUrl("https://agent.example.com"), "https://agent.example.com");
}

@test:Config {groups: ["a2a"]}
function testA2aUnreachableAgentErrorNamesTheAddressFromTheCard() returns error? {
    // A card that still lists an address the caller cannot reach, as when a gateway does not rewrite it.
    // Named so the relay model's tool call (askScriptedAgent) finds it.
    A2aToolKit toolkit = check new (a2aCard("Unreachable"), name = "scriptedAgent");
    Agent agent = check new (systemPrompt = {role: "Relay", instructions: "Pass every request on."},
        model = new A2aRelayMockLLM(), tools = [toolkit]);
    string reply = check agent.run("echo hello", sessionId = "gw-unreachable");
    test:assertTrue(reply.includes("calling http://localhost:1, the address in the agent's card"), reply);
}
