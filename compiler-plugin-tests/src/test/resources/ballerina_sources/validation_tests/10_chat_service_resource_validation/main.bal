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
import ballerina/http as h;

listener ai:Listener validListener = new (9201);
listener ai:Listener missingChatListener = new (9202);
listener ai:Listener tooManyParamsListener = new (9203);
listener ai:Listener zeroParamsListener = new (9204);
listener ai:Listener missingPayloadAnnotationListener = new (9205);
listener ai:Listener invalidHeadersTypeListener = new (9206);
listener ai:Listener unsupportedResourceListener = new (9207);
listener ai:Listener invalidPayloadTypeListener = new (9208);
listener ai:Listener invalidReturnTypeListener = new (9209);
listener ai:Listener aliasedImportListener = new (9210);

// No diagnostics expected: declares `chat` and nothing else.
service /valid on validListener {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        return {message: request.message};
    }
}

// Expect MISSING_CHAT_RESOURCE: declares `decision` but no `chat`.
service /missingChat on missingChatListener {
    resource function post decision(@http:Payload ai:DecisionMessage request) returns ai:ChatRespMessage|error {
        return {message: request.sessionId};
    }
}

// Expect INVALID_RESOURCE_PARAMETER_COUNT on both `chat` and `decision`: the dispatcher can only
// ever supply the payload and the headers, never a third value.
service /tooManyParams on tooManyParamsListener {
    resource function post chat(@http:Payload ai:ChatReqMessage request, http:Headers headers, string extra = "")
            returns ai:ChatRespMessage|error {
        return {message: request.message};
    }

    resource function post decision(@http:Payload ai:DecisionMessage request, http:Headers headers, string extra = "")
            returns ai:ChatRespMessage|error {
        return {message: request.sessionId};
    }
}

// Expect INVALID_RESOURCE_PARAMETER_COUNT on both `chat` and `decision`: neither resource can ever
// see the payload, which defeats the point of either one.
service /zeroParams on zeroParamsListener {
    resource function post chat() returns ai:ChatRespMessage|error {
        return {message: "ok"};
    }

    resource function post decision() returns ai:ChatRespMessage|error {
        return {message: "ok"};
    }
}

// Expect MISSING_PAYLOAD_ANNOTATION: the first parameter is unannotated, so Ballerina binds it as a
// query parameter, not the body the dispatcher actually sends.
service /missingPayloadAnnotation on missingPayloadAnnotationListener {
    resource function post chat(ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        return {message: request.message};
    }
}

// Expect INVALID_HEADERS_PARAMETER_TYPE: the second parameter is a `string`, not `http:Headers`,
// which is the only value the dispatcher ever puts there.
service /invalidHeadersType on invalidHeadersTypeListener {
    resource function post chat(@http:Payload ai:ChatReqMessage request, string headers)
            returns ai:ChatRespMessage|error {
        return {message: request.message};
    }
}

// Expect UNSUPPORTED_RESOURCE on `get health` only: `chat` is present and fine on its own.
service /unsupportedResource on unsupportedResourceListener {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        return {message: request.message};
    }

    resource function get health() returns string {
        return "ok";
    }
}

// Expect INVALID_PAYLOAD_PARAMETER_TYPE: the payload is annotated correctly, but its type can never
// hold the `ai:ChatReqMessage` value the dispatcher actually sends.
service /invalidPayloadType on invalidPayloadTypeListener {
    resource function post chat(@http:Payload string request) returns ai:ChatRespMessage|error {
        return {message: request};
    }
}

// Expect INVALID_RESOURCE_RETURN_TYPE: a `string` can never hold what the native adaptor and
// `toResponse` both expect back.
service /invalidReturnType on invalidReturnTypeListener {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns string {
        return request.message;
    }
}

// No diagnostics expected: `http` is imported under an alias, but the annotation and the headers
// type still resolve to the same `ballerina/http` module, so this must compile clean.
service /aliasedImport on aliasedImportListener {
    resource function post chat(@h:Payload ai:ChatReqMessage request, h:Headers headers)
            returns ai:ChatRespMessage|error {
        return {message: request.message};
    }
}
