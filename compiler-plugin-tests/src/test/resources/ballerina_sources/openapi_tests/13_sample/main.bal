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
import ballerina/http;

// Inline http:Listener passed via the named `listenOn` argument.
listener ai:Listener namedListener = new (listenOn = check new http:Listener(9091));

// Inline http:Listener passed positionally (without `listenOn`).
listener ai:Listener positionalListener = new (check new http:Listener(9092));

// Inline http:Listener wrapped in a parenthesized (braced) expression.
listener ai:Listener bracedListener = new (listenOn = check (new http:Listener(9093)));

// Inline http:Listener with named arguments in a different order (port not first) and a named host.
listener ai:Listener reorderedListener = new (listenOn = check new http:Listener(host = "127.0.0.1", port = 9094));

// Default HTTP listener, as scaffolded by the WSO2 Integrator (resolves to the default port 9090).
listener ai:Listener defaultListener = new (listenOn = check http:getDefaultListener());

service /namedService on namedListener {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        return {message: request.sessionId + ": " + request.message};
    }
}

service /positionalService on positionalListener {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        return {message: request.sessionId + ": " + request.message};
    }
}

service /bracedService on bracedListener {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        return {message: request.sessionId + ": " + request.message};
    }
}

service /reorderedService on reorderedListener {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        return {message: request.sessionId + ": " + request.message};
    }
}

service /defaultService on defaultListener {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        return {message: request.sessionId + ": " + request.message};
    }
}

// Anonymous inline ai:Listener defined directly on the service.
service /anonymousService on new ai:Listener(listenOn = check new http:Listener(9096)) {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        return {message: request.sessionId + ": " + request.message};
    }
}
