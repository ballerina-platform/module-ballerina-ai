// Copyright (c) 2023 WSO2 LLC (http://www.wso2.com).
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

import ballerina/http;
import ballerina/log;
import ballerina/mcp;

# Supported HTTP methods.
public enum HttpMethod {
    GET, POST, DELETE, PUT, PATCH, HEAD, OPTIONS
}

# Defines a HTTP parameter schema (can be query parameter or path parameters).
public type ParameterSchema record {|
    # Whether the parameter is a path or query parameter
    PATH|QUERY location;
    # A brief description of the parameter
    string description?;
    # Whether the parameter is mandatory
    boolean required?;
    # Describes how a specific property value will be serialized depending on its type
    EncodingStyle style?;
    # When this is true, property values of type array or object generate separate parameters for each value of the array, or key-value-pair of the map.
    boolean explode?;
    # Null value is allowed
    boolean nullable?;
    # Whether empty value is allowed
    boolean allowEmptyValue?;
    # Content type of the schema
    string mediaType?;
    # Parameter schema
    JsonSubSchema schema;
|};

# Defines an HTTP tool. This is a special type of tool that can be used to invoke HTTP resources.
public type HttpTool record {|
    # Name of the Http resource tool
    string name;
    # Description of the Http resource tool used by the LLM
    string description;
    # Http method type (GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS)
    HttpMethod method;
    # Path of the Http resource
    string path;
    # path and query parameters definitions of the Http resource
    map<ParameterSchema> parameters?;
    # Request body definition of the Http resource
    RequestBodySchema requestBody?;
|};

public type RequestBodySchema record {|
    # A brief description of the request body
    string description?;
    # Content type of the request body
    string mediaType?;
    # Request body schema
    JsonSubSchema schema;
|};

type HttpToolJsonSchema record {|
    *ObjectInputSchema;
    record {|
        ConstantValueSchema path;
        ObjectInputSchema parameters?;
        JsonSubSchema requestBody?;
    |} properties;
|};

// input record definitions ----------------------------
# Defines an HTTP input record.
type HttpInput record {|
    # Http tool record
    string path;
    # Path and query parameters for the Http resource
    map<json> parameters?;
    # Request body of the Http resource
    map<json> requestBody?;
|};

# Defines an HTTP parameters record for requests.
type HttpParameters record {|
    # Http path
    string path;
    # Http message
    json|xml message;
|};

# Defines an HTTP output record for requests.
public type HttpOutput record {|
    # HTTP status code of the response
    int code;
    # HTTP path url with encoded paramteres
    string path;
    # Response headers 
    record {|
        # Content type of the response
        string contentType?;
        # Content length of the response
        int contentLength?;
    |} headers;
    # Response payload
    json|xml body?;
|};

# Allows implmenting custom toolkits by extending this type. Toolkits can help to define new types of tools so that agent can understand them.
public type BaseToolKit distinct object {
    # Useful to retrieve the Tools extracted from the Toolkit.
    # + return - An array of Tools
    public isolated function getTools() returns ToolConfig[];
};

# Represents a base type for MCP toolkits.
public type McpBaseToolKit distinct isolated object {
    *BaseToolKit;
};

# Represents a toolkit for interacting with an MCP server, invoking tools via the MCP protocol.
public isolated class McpToolKit {
    *McpBaseToolKit;
    private final mcp:StreamableHttpClient mcpClient;
    private final ToolConfig[] & readonly tools;

    public isolated function init(string serverUrl, string[]? permittedTools = (),
            mcp:Implementation info = {name: "MCP Client", version: "1.0.0"},
            *mcp:StreamableHttpClientTransportConfig config) returns Error? {
        log:printDebug("Connecting to MCP server",
            serverUrl = serverUrl,
            clientInfo = info
        );

        mcp:StreamableHttpClient|mcp:ClientError mcpClient = new (serverUrl, config);
        if mcpClient is error {
            log:printDebug("Failed to connect to MCP server",
                mcpClient,
                serverUrl = serverUrl
            );
            return error Error("Failed to initialize the MCP client", mcpClient);
        }
        self.mcpClient = mcpClient;

        mcp:ClientError? initializeRes = self.mcpClient->initialize(info);
        if initializeRes is error {
            log:printDebug("Failed to initialize MCP client",
                initializeRes,
                serverUrl = serverUrl
            );
            return error Error("Failed to initialize the MCP client", initializeRes);
        }

        mcp:ListToolsResult|error listTools = self.mcpClient->listTools();
        if listTools is error {
            log:printDebug("Failed to retrieve tools from MCP server",
                listTools,
                serverUrl = serverUrl
            );
            return error Error("Failed to get tools from the MCP server", listTools);
        }
        mcp:ToolDefinition[] filteredTools = filterPermittedTools(listTools.tools, permittedTools);

        log:printDebug("Retrieved tools from MCP server",
            serverUrl = serverUrl,
            tools = listTools.tools,
            filteredTools = filteredTools
        );

        isolated function caller = self.callTool;

        self.tools = from mcp:ToolDefinition tool in filteredTools
            select {
                name: tool.name,
                description: tool.description ?: "",
                parameters: check getInputSchemaValues(tool).cloneReadOnly(),
                caller
            };
    }

    public isolated function callTool(mcp:CallToolParams params) returns mcp:CallToolResult|error {
        return self.mcpClient->callTool(params);
    }

    public isolated function getTools() returns ToolConfig[] => self.tools;
}

# Defines a HTTP tool kit. This is a special type of tool kit that can be used to invoke HTTP resources.
# Require to initialize the toolkit with the service url and http tools that are belongs to a single API. 
public isolated class HttpServiceToolKit {
    *BaseToolKit;
    private final map<HttpTool> & readonly httpTools;
    private final ToolConfig[] & readonly tools;
    private final map<string|string[]> & readonly headers;
    private final http:Client httpClient;
    private final string serviceUrl;

    # Initializes the toolkit with the given service url and http tools.
    #
    # + serviceUrl - The url of the service to be called
    # + httpTools - The http tools to be initialized
    # + clientConfig - The http client configuration associated to the tools
    # + headers - The http headers to be used in the requests
    # + returns - error if the initialization fails
    public isolated function init(string serviceUrl, HttpTool[] httpTools, http:ClientConfiguration clientConfig = {}, map<string|string[]> headers = {}) returns Error? {
        self.serviceUrl = serviceUrl;
        self.headers = headers.cloneReadOnly();
        http:Client|http:Error httpClient = new (serviceUrl, clientConfig);
        if httpClient is http:Error {
            return error Error("Failed to initialize HttpServiceToolKit", httpClient);
        }
        self.httpClient = httpClient;
        self.httpTools = map from HttpTool tool in httpTools
            select [string `${tool.path}:${tool.method}`, tool.cloneReadOnly()];

        ToolConfig[] tools = [];
        foreach HttpTool httpTool in httpTools {
            map<ParameterSchema>? params = httpTool?.parameters;
            RequestBodySchema? requestBody = httpTool?.requestBody;

            ObjectInputSchema? httpParameters = ();
            if params !is () && params.length() > 0 {
                string[] required = [];
                map<JsonSubSchema> properties = {};
                foreach [string, ParameterSchema] [name, 'parameter] in params.entries() {
                    if 'parameter.location == PATH || 'parameter.required == true {
                        required.push(name);
                    }
                    properties[name] = 'parameter.schema;
                }
                httpParameters = {
                    required,
                    properties
                };
            }

            HttpToolJsonSchema parameters = {
                properties: {
                    path: {'const: httpTool.path},
                    parameters: httpParameters,
                    requestBody: requestBody is () ? () : requestBody.schema
                }
            };

            isolated function caller = self.get;
            match httpTool.method {
                GET => { // do nothing (default)
                }
                POST => {
                    caller = self.post;
                }
                DELETE => {
                    caller = self.delete;
                }
                PUT => {
                    caller = self.put;
                }
                PATCH => {
                    caller = self.patch;
                }
                HEAD => {
                    caller = self.head;
                }
                OPTIONS => {
                    caller = self.options;
                }
                _ => {
                    return error Error("invalid http type: " + httpTool.method.toString());
                }
            }
            tools.push({
                name: httpTool.name,
                description: httpTool.description,
                parameters: {
                    properties: {
                        httpInput: parameters
                    },
                    required: ["httpInput"]
                },
                caller
            });
            self.tools = tools.cloneReadOnly();
        }
    }

    # Useful to retrieve the Tools extracted from the HttpTools.
    # + return - An array of Tools corresponding to the HttpTools
    public isolated function getTools() returns ToolConfig[] => self.tools;

    private isolated function get(HttpInput httpInput) returns HttpOutput|Error {
        do {
            HttpParameters httpParameters = check getHttpParameters(self.httpTools, GET, httpInput, false);
            log:printDebug("Executing HTTP GET request",
                serverUrl = self.serviceUrl,
                path = httpParameters.path,
                method = "GET"
            );
            http:Response getResult = check self.httpClient->get(httpParameters.path, headers = self.headers);
            log:printDebug("HTTP request completed",
                serverUrl = self.serviceUrl,
                path = httpParameters.path,
                method = "GET",
                statusCode = getResult.statusCode
            );
            return extractResponsePayload(httpParameters.path, getResult);
        } on fail error e {
            log:printDebug("HTTP request failed",
                serverUrl = self.serviceUrl,
                path = httpInput.path,
                method = "GET",
                errorMessage = e.message()
            );
            return handleHttpResourceDespatchError(e);
        }
    }

    private isolated function post(HttpInput httpInput) returns HttpOutput|Error {
        do {
            HttpParameters httpParameters = check getHttpParameters(self.httpTools, POST, httpInput, true);
            log:printDebug("Executing HTTP POST request",
                serverUrl = self.serviceUrl,
                path = httpParameters.path,
                method = "POST"
            );
            http:Response postResult = check self.httpClient->post(httpParameters.path, message = httpParameters.message, headers = self.headers);
            log:printDebug("HTTP request completed",
                serverUrl = self.serviceUrl,
                path = httpParameters.path,
                method = "POST",
                statusCode = postResult.statusCode
            );
            return extractResponsePayload(httpParameters.path, postResult);
        } on fail error e {
            log:printDebug("HTTP request failed",
                serverUrl = self.serviceUrl,
                path = httpInput.path,
                method = "POST",
                errorMessage = e.message()
            );
            return handleHttpResourceDespatchError(e);
        }
    }

    private isolated function delete(HttpInput httpInput) returns HttpOutput|Error {
        do {
            HttpParameters httpParameters = check getHttpParameters(self.httpTools, DELETE, httpInput, true);
            log:printDebug("Executing HTTP DELETE request",
                serverUrl = self.serviceUrl,
                path = httpParameters.path,
                method = "DELETE"
            );
            http:Response deleteResult = check self.httpClient->delete(httpParameters.path, message = httpParameters.message, headers = self.headers);
            log:printDebug("HTTP request completed",
                serverUrl = self.serviceUrl,
                path = httpParameters.path,
                method = "DELETE",
                statusCode = deleteResult.statusCode
            );
            return extractResponsePayload(httpParameters.path, deleteResult);
        } on fail error e {
            log:printDebug("HTTP request failed",
                serverUrl = self.serviceUrl,
                path = httpInput.path,
                method = "DELETE",
                errorMessage = e.message()
            );
            return handleHttpResourceDespatchError(e);
        }
    }

    private isolated function put(HttpInput httpInput) returns HttpOutput|Error {
        do {
            HttpParameters httpParameters = check getHttpParameters(self.httpTools, PUT, httpInput, true);
            log:printDebug("Executing HTTP PUT request",
                serverUrl = self.serviceUrl,
                path = httpParameters.path,
                method = "PUT"
            );
            http:Response putResult = check self.httpClient->put(httpParameters.path, message = httpParameters.message, headers = self.headers);
            log:printDebug("HTTP request completed",
                serverUrl = self.serviceUrl,
                path = httpParameters.path,
                method = "PUT",
                statusCode = putResult.statusCode
            );
            return extractResponsePayload(httpParameters.path, putResult);
        } on fail error e {
            log:printDebug("HTTP request failed",
                serverUrl = self.serviceUrl,
                path = httpInput.path,
                method = "PUT",
                errorMessage = e.message()
            );
            return handleHttpResourceDespatchError(e);
        }
    }

    private isolated function patch(HttpInput httpInput) returns HttpOutput|Error {
        do {
            HttpParameters httpParameters = check getHttpParameters(self.httpTools, PATCH, httpInput, true);
            log:printDebug("Executing HTTP PATCH request",
                serverUrl = self.serviceUrl,
                path = httpParameters.path,
                method = "PATCH"
            );
            http:Response patchResult = check self.httpClient->patch(httpParameters.path, message = httpParameters.message, headers = self.headers);
            log:printDebug("HTTP request completed",
                serverUrl = self.serviceUrl,
                path = httpParameters.path,
                method = "PATCH",
                statusCode = patchResult.statusCode
            );
            return extractResponsePayload(httpParameters.path, patchResult);
        } on fail error e {
            log:printDebug("HTTP request failed",
                serverUrl = self.serviceUrl,
                path = httpInput.path,
                method = "PATCH",
                errorMessage = e.message()
            );
            return handleHttpResourceDespatchError(e);
        }
    }

    private isolated function head(HttpInput httpInput) returns HttpOutput|Error {
        do {
            HttpParameters httpParameters = check getHttpParameters(self.httpTools, HEAD, httpInput, false);
            log:printDebug("Executing HTTP HEAD request",
                serverUrl = self.serviceUrl,
                path = httpParameters.path,
                method = "HEAD"
            );
            http:Response headResult = check self.httpClient->head(httpParameters.path, headers = self.headers);
            log:printDebug("HTTP request completed",
                serverUrl = self.serviceUrl,
                path = httpParameters.path,
                method = "HEAD",
                statusCode = headResult.statusCode
            );
            return extractResponsePayload(httpParameters.path, headResult);
        } on fail error e {
            log:printDebug("HTTP request failed",
                serverUrl = self.serviceUrl,
                path = httpInput.path,
                method = "HEAD",
                errorMessage = e.message()
            );
            return handleHttpResourceDespatchError(e);
        }
    }

    private isolated function options(HttpInput httpInput) returns HttpOutput|Error {
        do {
            HttpParameters httpParameters = check getHttpParameters(self.httpTools, OPTIONS, httpInput, false);
            log:printDebug("Executing HTTP OPTIONS request",
                serverUrl = self.serviceUrl,
                path = httpParameters.path,
                method = "OPTIONS"
            );
            http:Response optionsResult = check self.httpClient->options(httpParameters.path, headers = self.headers);
            log:printDebug("HTTP request completed",
                serverUrl = self.serviceUrl,
                path = httpParameters.path,
                method = "OPTIONS",
                statusCode = optionsResult.statusCode
            );
            return extractResponsePayload(httpParameters.path, optionsResult);
        } on fail error e {
            log:printDebug("HTTP request failed",
                serverUrl = self.serviceUrl,
                path = httpInput.path,
                method = "OPTIONS",
                errorMessage = e.message()
            );
            return handleHttpResourceDespatchError(e);
        }
    }
}

isolated function handleHttpResourceDespatchError(error e) returns Error {
    if e is Error {
        return e;
    }
    return error Error(e.message(), e);
}

isolated function filterPermittedTools(mcp:ToolDefinition[] tools, string[]? permittedTools) returns mcp:ToolDefinition[] {
    if permittedTools is () {
        return tools;
    }
    return from mcp:ToolDefinition tool in tools
        where permittedTools.indexOf(tool.name) is int
        select tool;
}

isolated function getInputSchemaValues(mcp:ToolDefinition tool) returns map<json>|Error {
    map<json>|error inputSchema = tool.inputSchema.cloneWithType();
    if inputSchema is error {
        return error Error(string `Failed to get the input schema for the tool: ${tool.name}`, inputSchema);
    }
    return inputSchema;
};

# Constructs the list of permitted MCP tool configurations by querying the MCP server.
#
# This function initializes the MCP client using the provided implementation information
# and retrieves the list of tools permitted for use. Each permitted tool is then associated
# with a corresponding MCP function tool dispatcher.
#
# A tool dispatcher is a function with the following signature:
# ```ballerina
# @ai:AgentTool
# isolated function (mcp:CallToolParams) returns mcp:CallToolResult|error;
# ```
#
# + mcpClient - The MCP client instance used to query the MCP server
# + info - The implementation information used to initialize the client
# + permittedTools - A map of tool names to their respective MCP function tool dispatchers,
# or a single dispatcher if all tools are permitted
# + return - An array of tool configurations or an error if the operation fails
public isolated function getPermittedMcpToolConfigs(mcp:StreamableHttpClient mcpClient, mcp:Implementation info,
        map<FunctionTool>|FunctionTool permittedTools) returns ToolConfig[]|Error {
    do {
        _ = check mcpClient->initialize(info);
        mcp:ListToolsResult listTools = check mcpClient->listTools();
        return from mcp:ToolDefinition tool in listTools.tools
            where permittedTools is FunctionTool || permittedTools.hasKey(tool.name)
            select {
                name: tool.name,
                description: tool.description ?: "",
                parameters: (<map<json>>tool.inputSchema).cloneReadOnly(),
                caller: permittedTools is FunctionTool ? permittedTools : permittedTools.get(tool.name)
            };
    } on fail error e {
        return error Error("failed to generate permitted MCP tool configurations", e);
    }
}
