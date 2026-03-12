// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
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
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/test;

const int MOCK_HTTP_SVC_PORT = 9095;
const MOCK_HTTP_SVC_URL = "http://localhost:9095/api";

// Simple mock HTTP service used to test HttpServiceToolKit execution.
service /api on new http:Listener(MOCK_HTTP_SVC_PORT) {

    resource function get items/[string itemId]() returns json {
        return {id: itemId, name: "test-item"};
    }

    resource function get search(string q = "") returns json {
        return {query: q, resultCount: 2};
    }

    resource function post items(@http:Payload json body) returns http:Created {
        json responseBody = {created: true, data: body};
        return {body: responseBody};
    }

    resource function put items/[string itemId](@http:Payload json body) returns json {
        return {id: itemId, updated: true};
    }

    resource function patch items/[string itemId](@http:Payload json body) returns json {
        return {id: itemId, patched: true};
    }

    resource function delete items/[string itemId]() returns http:NoContent {
        return {};
    }

    resource function head items/[string itemId]() returns http:Ok {
        return {};
    }

    resource function options items() returns json {
        return {methods: ["GET", "POST", "PUT", "PATCH", "DELETE"]};
    }
}

// HttpTool definitions for the mock service.
// Names are prefixed with "svc" to avoid conflicts with the module-level `httpTools` in toolkit-test.bal.
HttpTool[] httpSvcTools = [
    {
        name: "svcGet",
        description: "Get an item by ID",
        method: GET,
        path: "/items/{itemId}",
        parameters: {
            itemId: {location: PATH, schema: {'type: STRING}}
        }
    },
    {
        name: "svcSearch",
        description: "Search items with a query string",
        method: GET,
        path: "/search",
        parameters: {
            q: {location: QUERY, schema: {'type: STRING}}
        }
    },
    {
        name: "svcPost",
        description: "Create a new item",
        method: POST,
        path: "/items",
        requestBody: {
            schema: {
                properties: {
                    name: {'type: STRING}
                }
            }
        }
    },
    {
        name: "svcPut",
        description: "Replace an item by ID",
        method: PUT,
        path: "/items/{itemId}",
        parameters: {
            itemId: {location: PATH, schema: {'type: STRING}}
        },
        requestBody: {
            schema: {
                properties: {
                    name: {'type: STRING}
                }
            }
        }
    },
    {
        name: "svcPatch",
        description: "Partially update an item by ID",
        method: PATCH,
        path: "/items/{itemId}",
        parameters: {
            itemId: {location: PATH, schema: {'type: STRING}}
        },
        requestBody: {
            schema: {
                properties: {
                    name: {'type: STRING}
                }
            }
        }
    },
    {
        name: "svcDelete",
        description: "Delete an item by ID",
        method: DELETE,
        path: "/items/{itemId}",
        parameters: {
            itemId: {location: PATH, schema: {'type: STRING}}
        }
    },
    {
        name: "svcHead",
        description: "HEAD request for an item",
        method: HEAD,
        path: "/items/{itemId}",
        parameters: {
            itemId: {location: PATH, schema: {'type: STRING}}
        }
    },
    {
        name: "svcOptions",
        description: "OPTIONS request for items endpoint",
        method: OPTIONS,
        path: "/items"
    }
];

isolated function httpSvcToolKitExecutionDataProvider() returns [string, map<json>, int, boolean][] => [
    ["svcGet", {path: "/items/{itemId}", parameters: {itemId: "42"}}, 200, true],
    ["svcSearch", {path: "/search", parameters: {q: "ballerina"}}, 200, true],
    ["svcPost", {path: "/items", requestBody: {name: "widget"}}, 201, true],
    ["svcPut", {path: "/items/{itemId}", parameters: {itemId: "42"}, requestBody: {name: "updated-widget"}}, 200, true],
    ["svcPatch", {path: "/items/{itemId}", parameters: {itemId: "42"}, requestBody: {name: "patched-name"}}, 200, true],
    ["svcDelete", {path: "/items/{itemId}", parameters: {itemId: "42"}}, 204, false],
    ["svcHead", {path: "/items/{itemId}", parameters: {itemId: "42"}}, 200, false],
    ["svcOptions", {path: "/items"}, 200, true]
];

@test:Config {
    groups: ["http-service-toolkit"],
    dataProvider: httpSvcToolKitExecutionDataProvider
}
function testHttpSvcToolKitExecution(string toolName, map<json> httpInput, int expectedCode, boolean expectBody)
        returns error? {
    HttpServiceToolKit toolkit = check new (MOCK_HTTP_SVC_URL, httpSvcTools);
    ToolStore store = check new (toolkit);
    ToolOutput output = check store.execute({
        name: toolName,
        arguments: {httpInput: httpInput}
    });
    anydata|error value = output.value;
    if value !is HttpOutput {
        test:assertFail(string `Expected HttpOutput, got: ${(typeof value).toString()}`);
    }
    test:assertEquals(value.code, expectedCode);
    if expectBody {
        test:assertTrue(value?.body !is (), string `Expected non-empty response body for ${toolName}`);
    } else {
        test:assertTrue(value?.body is (), string `Expected empty response body for ${toolName}`);
    }
}

// Custom headers test stays separate since it requires a different toolkit configuration.
@test:Config {groups: ["http-service-toolkit"]}
function testHttpSvcToolKitWithCustomHeaders() returns error? {
    map<string|string[]> customHeaders = {
        "X-Custom-Header": "test-value",
        "X-Request-Id": "12345"
    };
    HttpServiceToolKit toolkit = check new (MOCK_HTTP_SVC_URL, [httpSvcTools[0]], headers = customHeaders);
    ToolStore store = check new (toolkit);
    ToolOutput output = check store.execute({
        name: "svcGet",
        arguments: {
            httpInput: {
                path: "/items/{itemId}",
                parameters: {itemId: "99"}
            }
        }
    });
    anydata|error value = output.value;
    if value !is HttpOutput {
        test:assertFail(string `Expected HttpOutput, got: ${(typeof value).toString()}`);
    }
    test:assertEquals(value.code, 200);
}

// Not-found test stays separate since it uses a different tool set and toolkit.
@test:Config {groups: ["http-service-toolkit"]}
function testHttpSvcToolKitNotFoundResponse() returns error? {
    HttpTool notFoundTool = {
        name: "svcNotFound",
        description: "GET a non-existent resource",
        method: GET,
        path: "/nonexistent"
    };
    HttpServiceToolKit toolkit = check new (MOCK_HTTP_SVC_URL, [notFoundTool]);
    ToolStore store = check new (toolkit);
    ToolOutput output = check store.execute({
        name: "svcNotFound",
        arguments: {
            httpInput: {
                path: "/nonexistent"
            }
        }
    });
    anydata|error value = output.value;
    if value !is HttpOutput {
        test:assertFail(string `Expected HttpOutput for 404 response, got: ${(typeof value).toString()}`);
    }
    test:assertEquals(value.code, 404);
}
