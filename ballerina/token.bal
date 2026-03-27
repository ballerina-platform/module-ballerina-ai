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

isolated function getToolScopes(Credential agentCredential, AgentIdAuthConfig agentIdAuthConfig, 
    cache:Cache tokenManager, string toolName, Context context) returns 
    TokenAcquisitionError|InsufficientScopeError|TokenValidationError|map<()>?  {
    string agentId = agentCredential.id;
    boolean needsRefresh = true;
    map<()> scopeInToken = {};
    string|string[]? scopes = agentIdAuthConfig.scopes;
    string baseUrl = agentIdAuthConfig.baseAuthUrl;
    baseUrl = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() -1) : baseUrl;
    if tokenManager.hasKey(toolName) {
        any|error token = tokenManager.get(toolName);
        if token is TokenCache {
            needsRefresh = token.isAccessTokenExpired();
            scopeInToken = token.getScopes();
        }
    }
    if needsRefresh {
        log:printDebug("Requesting a new token for tool: ",
                agentId = agentId,
                toolName = toolName,
                scopes = scopes
        );
        http:Client|http:ClientError httpclient = new (baseUrl, 
            secureSocket = agentIdAuthConfig.secureSocket);
        if  httpclient is http:ClientError {
            return error TokenAcquisitionError(httpclient.message());
        }   
        Token freshToken = check getFreshToken(agentCredential, agentIdAuthConfig, agentId, 
                scopes, toolName, httpclient, baseUrl);
        error|map<()> validateTokenResult = validateToken(toolName, freshToken, tokenManager);
        if validateTokenResult is error {
            return error TokenValidationError(validateTokenResult.message());
        }
        return validateTokenResult;
    }
    return scopeInToken;
}

isolated function getFreshToken(Credential agentCredential, AgentIdAuthConfig agentIdConfig, 
        string agentId, string|string[]? scopes, string toolName, http:Client httpclient, 
        string baseUrl) returns TokenAcquisitionError|Token {
    observe:InvokeAuthorizeEndpointSpan invokeAuthorizeEndpointSpan = 
                    observe:createInvokeAuthorizeEndpointSpan("WSO2");
    Pkce? pkce = ();
    if (agentIdConfig.isPkceEnabled) {
        Pkce|error result = generatePkce();
        if result is error {
            log:printError("Failed to create pkce value", 'error = result, agentId = agentId, 
                toolName = toolName);
            return error TokenAcquisitionError("Failed to create pkce value", 
                detail = {cause: result});
        }
        pkce = result;
    }
    string? clientId = agentIdConfig.clientId;
    if clientId is () {
        return error TokenAcquisitionError("Authorization is required to use this tool, " + 
            "but the client id is not configured.");
    } 
    string? redirectUri = agentIdConfig.redirectUri;
    if redirectUri is () {
        return error TokenAcquisitionError("Authorization is required to use this tool, " + 
            "but the redirect uri is not configured.");
    } 
    invokeAuthorizeEndpointSpan.addAuthRequestDetails(clientId, scopes, baseUrl, 
            challenge = pkce is Pkce ? pkce.challenge : ());
    AuthResponse|error flowId = getFlowId(clientId, redirectUri , agentId, scopes, 
            pkce, httpclient, agentIdConfig?.clientSecret);
    if flowId is error {
        invokeAuthorizeEndpointSpan.close(flowId);
        log:printError("Failed to obtain flow id for token acquisition",
                'error = flowId, agentId = agentId, toolName = toolName);
        return error TokenAcquisitionError("Failed to obtain flow id", detail = {cause: flowId});
    }
    invokeAuthorizeEndpointSpan.close();
    log:printDebug("Successfully obtained flow id for token acquisition", agentId = agentId, 
            toolName = toolName);

    observe:AgentAuthenticationSpan authenticationSpan = 
            observe:createAgentAuthenticationSpan(flowId.flowId);
    authenticationSpan.addAgentIdentity(agentId, flowId.nextStep.authenticators[0].authenticatorId);
    Code|error code = getCode(flowId, agentCredential, httpclient);
    if code is error {
        authenticationSpan.close(code);
        log:printError("Failed to obtain authorization code for token acquisition", 
                'error = code, agentId = agentId, toolName = toolName);
        return error TokenAcquisitionError("Failed to obtain authorization code", 
            detail = {cause: code});
    }
    authenticationSpan.close();
    log:printDebug("Successfully obtained authorization code", agentId = agentId,
             toolName = toolName);

    observe:ExchangeTokenSpan exchangeTokenSpan = observe:createExchangeTokenSpan();
    exchangeTokenSpan.addExchangeDetails(clientId);
    error|Token token = getToken(code.authData.code, clientId, redirectUri , agentId, pkce, httpclient, 
        agentIdConfig?.clientSecret);
    if token is error {
        exchangeTokenSpan.close(token);
        log:printError("Failed to obtain access token", 'error = token, 
                agentId = agentId, toolName = toolName);
        return error TokenAcquisitionError("Failed to obtain access token", 
            detail = {cause: token});
    }
    exchangeTokenSpan.close();
    log:printDebug("Successfully obtained access token", agentId = agentId, 
        toolName = toolName);
    return token;
}

isolated function getFlowId(string clientId, string redirectUri, string agentId, string|string[]? scope, Pkce? pkce, 
                http:Client httpclient, string? clientSecret = ()) returns error|AuthResponse {
    log:printDebug("Requesting flow id and authenticator id for token acquisition", 
        agentId = agentId, scope = scope);
    string scopes = scope is string[] ? string:'join(SPACE, ...scope) : (scope is string ? scope : "");
    map<string> formData = {
        client_id: clientId,
        response_type: CODE,
        scope: scopes,
        redirect_uri: redirectUri,
        response_mode: DIRECT
    };
    if clientSecret is string {
        formData["client_secret"] =  clientSecret;
    }
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
    return httpclient->/authorize.post(output, {"Content-Type": APPLICATION_X_WWW_FORM_URLENCODED});
}

isolated function getCode(AuthResponse authResponse, Credential agentCredential, http:Client httpclient) returns error|Code {
    log:printDebug("Requesting authorization code for token acquisition", agentId = agentCredential.id);
    json payload = {
        flowId: authResponse.flowId,
        selectedAuthenticator: {
            authenticatorId: authResponse.nextStep.authenticators[0].authenticatorId,
            params: {
                username: agentCredential.id,
                password: agentCredential.secret

            }
        }
    };
    return httpclient->/authn.post(payload, {"Content-Type": APPLICATION_JSON}); 
}

isolated function getToken(string code, string clientId, string redirectUri, string agentId, Pkce? pkce, 
                http:Client httpclient, string? clientSecret = ()) returns error|Token {
    log:printDebug("Requesting access token for token acquisition", agentId = agentId);
    map<string> formData = {
        client_id: clientId,
        grant_type: AUTHORIZATION_CODE,
        code: code,
        redirect_uri: redirectUri
    };
    if clientSecret is string {
        formData["client_secret"] =  clientSecret;
    }
    if pkce is Pkce {
        formData["code_verifier"] = pkce.verifier;
    }
    string[] messageParams = [];
    foreach var [k, v] in formData.entries() {
        string encoded = check url:encode(v.toString(), UTF8_ENCODING);
        messageParams.push(string `${k}=${encoded}`);
    }
    return httpclient->/token.post(strings:'join(AMPERSAND, ...messageParams), 
        {"Content-Type": APPLICATION_X_WWW_FORM_URLENCODED});
}

isolated function addToken(string toolName, Token token, cache:Cache tokenManager) returns map<()> {
    TokenCache tokenCache = new (token);
    cache:Error? output = tokenManager.put(toolName, tokenCache);
    if output is cache:Error {
        log:printError("Failed to store token in cache", output, toolName = toolName);
    }
    return tokenCache.getScopes();
}

isolated function validateToken(string toolName, Token token, cache:Cache tokenManager) returns error| map<()> {
    observe:ValidateTokenSpan validateTokenSpan = observe:createValidateTokenSpan("WSO2");
    jwt:Payload decode = (check jwt:decode(token.access_token))[1];
    [int, decimal] currentTime = time:utcNow();
    if (currentTime[0] <= decode?.exp) {
        token.scope = decode["scope"].toString();
        token.expires_in = <int>decode["exp"];
        validateTokenSpan.addValidationResult(true, decode["client_id"].toString(), decode?.sub);
        validateTokenSpan.close();
        return addToken(toolName, token, tokenManager);
    }
    validateTokenSpan.addValidationResult(false, decode["client_id"].toString(), decode?.sub);
    validateTokenSpan.close();
    return {};
} 

isolated function validateToolScope(map<()> scopesInToken, string toolName, string|string[]? scopes, 
        string agentId) returns InsufficientScopeError? {
    observe:ValidateToolAuthorizationSpan toolAuthorizationSpan = observe:createValidateToolAuthorizationSpan(toolName);
    log:printDebug("Validating scopes for tool: ",
            agentId = agentId,
            toolName = toolName,
            requiredScopes = scopes
    );
    string[] requiredScopes = getRequiredScope(scopes);
    toolAuthorizationSpan.addScopeCheck(requiredScopes, scopesInToken.keys());
    foreach string scope in requiredScopes {
        if !scopesInToken.hasKey(scope) {
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
    log:printDebug("Successfully validated scopes", agentId = agentId, toolName = toolName);
    return;
}

isolated function getRequiredScope(string|string[]? scopes) returns string[] {
    if scopes is string[] {
        return scopes;
    } else if scopes is string {
        return [scopes];
    } else {
        return [];
    }
}

isolated function generateVerifier(int length) returns string|error {
    string out = EMPTY_STRING;
    foreach int i in 0 ... length - 1 {
        int idx = check random:createIntInRange(0, PKCE_CODE_VERIFIER_CHARSET.length());
        out += PKCE_CODE_VERIFIER_CHARSET.substring(idx, idx + 1);
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

isolated function generatePkce() returns Pkce|error {
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
    private map<()> scopes = {}; // Use a map instead of an array to reduce the lookup time.

    # Initializes the token cache with default empty values.
    isolated function init(Token token, decimal clockSkew = 10) {
        self.accessToken = token.access_token;
        self.expTime = token.expires_in - <int>clockSkew;
        string? tokenScopes = token?.scope;
        if tokenScopes is string {
            foreach string scope in re ` `.split(tokenScopes) {
                lock {
	                self.scopes[scope] = ();
                }
            }
        }
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
    isolated function getScopes() returns map<()> {
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
