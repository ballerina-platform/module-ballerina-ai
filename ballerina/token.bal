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

import ai.observe;
import ballerina/cache;
import ballerina/crypto;
import ballerina/http;
import ballerina/jwt;
import ballerina/lang.'string as strings;
import ballerina/lang.regexp;
import ballerina/log;
import ballerina/random;
import ballerina/time;
import ballerina/url;

type AuthorisedResponse record {
    string flowId;
    json authenticators;
};

type Authenticator record {
    string authenticatorId;
};

type NextStep record {
    Authenticator[] authenticators;
};

type AuthResponse record {
    string flowId;
    NextStep nextStep;
};

type CodeResponse record {
    string flowId;
};

type Pkce record {|
    string verifier;
    string challenge;
|};

type Token record {
    string access_token;
    int expires_in;
    string scope?;
    string refresh_token?;
    string token_type;
};

type Code record {
    record {string code;} authData;
};

# Represents the validation response.
#
# + scope - A JSON string containing a space-separated list of scopes associated with this token
# + client_id - Client identifier for the OAuth 2.0 client, which requested this token
# + exp - Expiry time (seconds since the Epoch)
# + active - Indicates whether the token is currently active.
type ValidationResponse record {
    string scope?;
    string client_id;
    int exp;
    boolean active?;
};

isolated function getToolScopes(AuthConfig auth, string baseUrl, cache:Cache tokenManager, 
        string toolName, string|string[] scopes, Context context, http:Client httpclient) 
            returns TokenAcquisitionError|InsufficientScopeError|TokenValidationError|string[] {
    string agentId = auth.agentId;
    boolean needsRefresh = true;
    string[] scopeInToken = [];
    string & readonly tokenValue = EMPTY_STRING;
    if tokenManager.hasKey(toolName) {
        any|error token = tokenManager.get(toolName);
        if token is TokenCache {
            needsRefresh = token.isAccessTokenExpired();
            scopeInToken = token.getScopes();
            tokenValue = token.getAccessToken();
        }
    }
    if needsRefresh {
        log:printDebug("Requesting a new token for tool: ",
                agentId = agentId,
                toolName = toolName,
                scopes = scopes
        );
        
        Token freshToken = check getFreshToken(auth, baseUrl, scopes, toolName, httpclient);

        observe:ValidateTokenSpan createValidateTokenSpan = observe:createValidateTokenSpan("WSO2:Asgardeo");
        ValidationResponse|error validateTokenResult = validateToken(auth, baseUrl, 
            freshToken.access_token, freshToken.token_type);
        if validateTokenResult is error {
            createValidateTokenSpan.addValidationResult(false, auth.clientId, auth.agentId);
            createValidateTokenSpan.close(validateTokenResult);
            log:printError("Token validation failed", 'error = validateTokenResult, 
                agentId = auth.agentId, toolName = toolName);
            return error TokenValidationError("Token validation failed: ", 
                cause = validateTokenResult);
        }
        boolean? active = validateTokenResult.active;
        createValidateTokenSpan.addValidationResult(active, auth.clientId, auth.agentId);
        if active is () || active is true {
            freshToken.expires_in = validateTokenResult.exp;
            freshToken.scope = validateTokenResult.scope;
            tokenValue = freshToken.access_token;
            scopeInToken = addToken(toolName, freshToken, tokenManager);
            log:printDebug("Setting token in the context for MCP tool: ", 
                agentId = agentId, toolName = toolName);
        } else {
            string msg = "Token validation failed: token is expired or revoked";
            createValidateTokenSpan.close(error TokenValidationError(msg));
            log:printError(msg, agentId = auth.agentId, toolName = toolName);
            return error TokenValidationError(msg);
        }
        createValidateTokenSpan.close();
    }
    context.setAccessToken(toolName, tokenValue);
    return scopeInToken;
}

isolated function validateToolScope(string[] cachedScopes, string toolName, string|string[] scopes, 
        string agentId) returns InsufficientScopeError? {
    observe:ValidateToolAuthorizationSpan toolAuthorizationSpan = observe:createValidateToolAuthorizationSpan(toolName);
    log:printDebug("Validating scopes for tool: ",
            agentId = agentId,
            toolName = toolName,
            requiredScopes = scopes
    );
    string[] requiredScopes = scopes is string[] ? scopes : [scopes];
    toolAuthorizationSpan.addScopeCheck(requiredScopes, cachedScopes);
    foreach string scope in requiredScopes {
        if cachedScopes.indexOf(scope) is () {
            log:printError("Scope mismatch detected for tool: ",
                    agentId = agentId,
                    toolName = toolName,
                    missingScope = scope
            );
            InsufficientScopeError err = error InsufficientScopeError("Requested OAuth scope is " +
                "not permitted or does not match the existing token scopes: " + scope);
            toolAuthorizationSpan.close(err);
            return err;
        }
    }
    toolAuthorizationSpan.close();
    log:printInfo("Successfully validated scopes", agentId = agentId, toolName = toolName);
    return;
}

isolated function getFreshToken(AuthConfig auth, string baseUrl, string|string[] scopes, 
        string toolName, http:Client httpclient) returns TokenAcquisitionError|Token {
    observe:InvokeAuthorizeEndpointSpan invokeAuthorizeEndpointSpan = 
                    observe:createInvokeAuthorizeEndpointSpan("WSO2");
    Pkce? pkce = ();
    if (auth.isPkceEnabled) {
        Pkce|error result = generatePKCE();
        if result is error {
            log:printError("Failed to create pkce value", 'error = result, agentId = auth.agentId, 
                toolName = toolName);
            return error TokenAcquisitionError("Failed to create pkce value", 
                detail = {cause: result});
        }
        pkce = result;
    }
    invokeAuthorizeEndpointSpan.addAuthRequestDetails(auth.clientId, 
                scopes, challenge= pkce is Pkce ? pkce.challenge : ());
    AuthResponse|error flowId = getFlowId(auth, baseUrl, scopes, pkce, httpclient);
    if flowId is error {
        invokeAuthorizeEndpointSpan.close(flowId);
        log:printError("Failed to obtain flow id for token acquisition",
                'error = flowId, agentId = auth.agentId, toolName = toolName);
        return error TokenAcquisitionError("Failed to obtain flow id", detail = {cause: flowId});
    }
    invokeAuthorizeEndpointSpan.close();
    log:printInfo("Successfully obtained flow id for token acquisition", agentId = auth.agentId, 
            toolName = toolName);

    observe:AgentAuthenticationSpan authenticationSpan = 
            observe:createAgentAuthenticationSpan(flowId.flowId);
    authenticationSpan.addAgentIdentity(auth.agentId, flowId.nextStep.authenticators[0].authenticatorId);
    Code|error code = getCode(flowId, auth, baseUrl, httpclient);
    if code is error {
        authenticationSpan.close(code);
        log:printError("Failed to obtain authorization code for token acquisition", 
                'error = code, agentId = auth.agentId, toolName = toolName);
        return error TokenAcquisitionError("Failed to obtain authorization code", 
            detail = {cause: code});
    }
    authenticationSpan.close();
    log:printInfo("Successfully obtained authorization code", agentId = auth.agentId,
             toolName = toolName);

    observe:ExchangeTokenSpan exchangeTokenSpan = observe:createExchangeTokenSpan();
    exchangeTokenSpan.addExchangeDetails(code.authData.code, 
            pkce is Pkce ? pkce.verifier : (), auth.clientId);
    error|Token token = getToken(code.authData.code, auth, baseUrl, pkce, httpclient);
    if token is error {
        exchangeTokenSpan.close(token);
        log:printError("Failed to obtain access token", 'error = token, 
                agentId = auth.agentId, toolName = toolName);
        return error TokenAcquisitionError("Failed to obtain access token", 
            detail = {cause: token});
    }
    exchangeTokenSpan.close();
    log:printInfo("Successfully obtained access token", agentId = auth.agentId, 
        toolName = toolName);
    return token;
}

isolated function getFlowId(AuthConfig auth, string baseUrl, string|string[] scope, Pkce? pkce, 
                http:Client httpclient) returns error|AuthResponse {
    log:printDebug("Requesting flow id and authenticator id for token acquisition", 
        agentId = auth.agentId, scope = scope);
    string scopes = scope is string[] ? string:'join(SPACE, ...scope) : scope;
    map<string> formData = {
        client_id: auth.clientId,
        response_type: CODE,
        scope: scopes,
        redirect_uri: auth.redirectUri,
        response_mode: DIRECT
    };
    if pkce is Pkce {
        formData["code_challenge"] = pkce.challenge;
        formData["code_challenge_method"] = CODE_CHALLENGE_S256;
    }
    string[] messageParams = [];
    string output;
    foreach var [k, v] in formData.entries() {
        string encoded = check url:encode(v.toString(), UTF8_ENCODING);
        messageParams.push(string `${k}=${encoded}`);
    }
    output = strings:'join(AMPERSAND, ...messageParams);

    http:Request req = new;
    req.setHeader("Content-Type", APPLICATION_X_WWW_FORM_URLENCODED);
    req.setPayload(output);
    return httpclient->post(AUTHORIZE, req);
}

isolated function getCode(AuthResponse authResponse, AuthConfig auth, string baseUrl, 
                http:Client httpclient) returns error|Code {
    log:printDebug("Requesting authorization code for token acquisition", agentId = auth.agentId);
    json payload = {
        "flowId": authResponse.flowId,
        "selectedAuthenticator": {
            "authenticatorId": authResponse.nextStep.authenticators[0].authenticatorId,
            "params": {
                "username": auth.agentId,
                "password": auth.agentSecret

            }
        }
    };
    http:Request req = new;
    req.setHeader("Content-Type", APPLICATION_JSON);
    req.setJsonPayload(payload);
    return httpclient->post(AUTHN_HEADER, req);
}

isolated function getToken(string code, AuthConfig auth, string baseUrl, Pkce? pkce, 
                http:Client httpclient) returns error|Token {
    log:printDebug("Requesting access token for token acquisition", agentId = auth.agentId);
    map<string> formData = {
        client_id: auth.clientId,
        grant_type: AUTHORIZATION_CODE,
        code: code,
        redirect_uri: auth.redirectUri
    };
    if pkce is Pkce {
        formData["code_verifier"] = pkce.verifier;
    }
    string[] messageParams = [];
    foreach var [k, v] in formData.entries() {
        string encoded = check url:encode(v.toString(), UTF8_ENCODING);
        messageParams.push(string `${k}=${encoded}`);
    }
    http:Request req = new;
    req.setHeader("Content-Type", APPLICATION_X_WWW_FORM_URLENCODED);
    req.setPayload(strings:'join(AMPERSAND, ...messageParams));
    return httpclient->post(TOKEN, req);
}

isolated function addToken(string toolName, Token token, cache:Cache tokenManager) returns string[] {
    TokenCache tokenCache = new (token);
    cache:Error? output = tokenManager.put(toolName, tokenCache);
    if output is cache:Error {
        log:printError("Failed to store token in cache", output, toolName = toolName);
    }
    return tokenCache.getScopes();
}

isolated function validateToken(AuthConfig auth, string baseUrl, string accessToken,
        string tokenTypeHint) returns error|ValidationResponse {
    Jwt|Introspection validation = auth.tokenValidation;
    if validation is Jwt {
        string? url = validation?.jwksConfig?.url;
        if url is string {
            return validateWithJwks(accessToken, url, auth);
        }
        string|crypto:PublicKey? certFile = validation?.certFile;
        if certFile is string|crypto:PublicKey {
            return validateWithCertificate(accessToken, certFile);
        }
        return error TokenValidationError("No valid JWT validation configuration found");
    }

    string? url = validation.introspectionUrl;
    string introspectUrl = url is string ? url : baseUrl.concat(INTROSPECT);
    return validateWithIntrospection(
            introspectUrl,
            accessToken,
            auth.agentId,
            validation.clientConfig,
            tokenTypeHint
    );
}

isolated function validateWithJwks(string token, string url, AuthConfig auth) 
        returns error|ValidationResponse {
    log:printDebug("Validating token using JWKS", agentId = auth.agentId);
    jwt:ValidatorConfig validatorConfig = {
        signatureConfig: {
            jwksConfig: {
                url: url
            }
        }
    };
    jwt:Payload result = check jwt:validate(token, validatorConfig);
    return result.cloneWithType(ValidationResponse);
}

isolated function validateWithCertificate(string token, string|crypto:PublicKey certificate) 
        returns error|ValidationResponse {
    jwt:ValidatorConfig validatorConfig = {
        signatureConfig: {
            certFile: certificate
        }
    };
    jwt:Payload result = check jwt:validate(token, validatorConfig);
    return result.cloneWithType(ValidationResponse);
}

isolated function validateWithIntrospection(string url, string accessToken, string agentId, 
        ClientCredentialsConfig clientConfig, string? tokenTypeHint) returns ValidationResponse|error {
    log:printDebug("Validating token using introspection", agentId = agentId);
    string textPayload = TOKEN_WITH_EQUAL + accessToken;
    if tokenTypeHint is string {
        textPayload += TOKEN_TYPE_HINT + tokenTypeHint;
    }
    http:Client httpclient = check new (url, auth = {username: clientConfig.clientId, 
        password: clientConfig.clientSecret});
    http:Request req = new;
    req.setHeader(CONTENT_TYPE_HEADER, APPLICATION_X_WWW_FORM_URLENCODED);
    req.setPayload(textPayload);
    return httpclient->post(EMPTY_STRING, req);
}

isolated function generateVerifier(int length) returns string|error {
    string out = EMPTY_STRING;
    foreach int i in 0 ... length - 1 {
        int idx = check random:createIntInRange(0, CHARSET.length());
        out += CHARSET.substring(idx, idx + 1);
    }
    return out;
}

isolated function base64UrlEncode(byte[] data) returns string {
    string base = data.toBase64();
    base = regexp:replaceAll(re `\+`, base, DASH);
    base = regexp:replaceAll(re `/`, base, UNDERSCORE);
    base = regexp:replaceAll(re `=`, base, EMPTY_STRING);
    return base;
}

isolated function generatePKCE() returns Pkce|error {
    string verifier = check generateVerifier(64);
    byte[] hash = crypto:hashSha256(verifier.toBytes());
    return {
        verifier: verifier,
        challenge: base64UrlEncode(hash)
    };
}

# Represents a thread-safe cache for storing and managing an OAuth access token, its expiry time,
# and associated scopes.
isolated class TokenCache {

    private string accessToken;
    private int expTime;
    private string[] scopes;

    # Initializes the token cache with default empty values.
    isolated function init(Token token, decimal clockSkew = 10) {
        self.accessToken = token.access_token;
        self.expTime = token.expires_in - <int>clockSkew;
        string? scope = token?.scope;
        self.scopes = scope is string ? re ` `.split(scope) : [];
    }

    # Returns the currently cached access token.
    #
    # + return - The cached access token string
    isolated function getAccessToken() returns string {
        lock {
            return self.accessToken;
        }
    }

    # Returns a cloned list of scopes associated with the cached access token.
    #
    # + return - A cloned array of scopes linked to the access token
    isolated function getScopes() returns string[] {
        lock {
            return self.scopes.clone();
        }
    }

    # Checks whether the cached access token has expired based on the current UTC time.
    #
    # + return - True if the access token has expired, otherwise false
    isolated function isAccessTokenExpired() returns boolean {
        lock {
            [int, decimal] currentTime = time:utcNow();
            return currentTime[0] >= self.expTime;
        }
    }
}
