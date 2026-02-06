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

import ballerina/cache;
import ballerina/http;
import ballerina/lang.'string as strings;
import ballerina/log;
import ballerina/time;
import ballerina/url;
import ballerina/jwt;
import ballerina/crypto;
import ballerina/random;
import ballerina/lang.regexp;

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

# Represents the validation response.
#
# + scope - A JSON string containing a space-separated list of scopes associated with this token
# + client_id - Client identifier for the OAuth 2.0 client, which requested this token
# + exp - Expiry time (seconds since the Epoch)
type ValidationResponse record {
    string scope?;
    string client_id;
    int exp;
};

isolated function getToolScopes(AuthConfig auth, string baseUrl, cache:Cache tokenManager, string toolName, 
                                string|string[] scopes, Context context, boolean isMcpTool) 
                        returns TokenAcquisitionError|MissMatchScopeError|TokenValidationError|string[] {
    string agentId = auth.agentId;
    boolean needsRefresh = true;
    string[] scopeInToken = [];
    string & readonly tokenValue = EMPTY_STRING;
    if tokenManager.hasKey(toolName) {
       any|error token = tokenManager.get(toolName);
       if (token is TokenCache) {
           TokenCache tokenCache = <TokenCache>token;
           needsRefresh = tokenCache.isAccessTokenExpired();
           scopeInToken = tokenCache.getScopes(); 
           tokenValue = tokenCache.getAccessToken();
       }
    }
    if needsRefresh {
        log:printInfo("Requesting a new token for tool: ",
            agentId = agentId,
            toolName = toolName,
            scopes = scopes
        );
        Token freshToken = check getFreshToken(auth, baseUrl, scopes, toolName);
        ValidationResponse|error validateTokenResult = validateToken(auth, baseUrl, freshToken.access_token, freshToken.token_type);
        if validateTokenResult is error {
            log:printError("Token validation failed", 'error = validateTokenResult, agentId = auth.agentId, toolName = toolName);
            return error TokenValidationError("Token validation failed: ", detail = {cause: validateTokenResult});
        }
        freshToken.expires_in = validateTokenResult.exp;
        freshToken.scope = validateTokenResult.scope;
        tokenValue = freshToken.access_token;
        scopeInToken = addToken(toolName, freshToken, tokenManager);
        if isMcpTool {
            log:printInfo("Setting token in the context for MCP tool: ", agentId = agentId, toolName = toolName);
            context.setAccessToken(toolName, tokenValue);
        }
    }
    return scopeInToken;
}

isolated function validateToolScope(string[] cachedScopes, string toolName, string|string[] scopes) 
                  returns MissMatchScopeError? {
    log:printInfo("Validating scopes for tool: ",
           toolName = toolName,
           requiredScopes = scopes
    );
    string[] requiredScopes;
    if scopes is string {
       requiredScopes = [scopes];
    } else {
       requiredScopes = scopes;
    }
    foreach string scope in requiredScopes {
       if cachedScopes.indexOf(scope) is () {
            log:printError("Scope mismatch detected for tool: ",
                   toolName = toolName,
                   missingScope = scope
            );
            return error MissMatchScopeError("Requested OAuth scope is not permitted or does not" + 
                    "match the existing token scopes: " + scope);
       }
    }
    return;
}

isolated function getFreshToken(AuthConfig auth, string baseUrl, string|string[] scopes, string toolName) 
               returns TokenAcquisitionError|Token {
    Pkce? pkce = ();
    if (auth.isPkceEnabled) {
        pkce = generatePKCE();
    }
    
    AuthResponse|error flowId = getFlowId(auth, baseUrl, scopes, pkce);
    if flowId is error {
       log:printError("Failed to obtain flow id for token acquisition", 
                'error = flowId, agentId = auth.agentId, toolName = toolName);
       return error TokenAcquisitionError("Failed to obtain flow id", detail = {cause: flowId});
    }
    log:printInfo("Successfully obtained flow id for token acquisition", agentId = auth.agentId, toolName = toolName);

    error|string code = getCode(flowId, auth, baseUrl);
    if code is error {
       log:printError("Failed to obtain authorization code for token acquisition", 'error = code, 
                agentId = auth.agentId, toolName = toolName);
       return error TokenAcquisitionError("Failed to obtain authorization code", detail = {cause: code});
    }
    log:printInfo("Successfully obtained authorization code", agentId = auth.agentId, toolName = toolName);

    error|Token token = getToken(code, auth, baseUrl, pkce);
    if token is error {
       log:printError("Failed to obtain access token", 'error = token, agentId = auth.agentId, toolName = toolName);
       return error TokenAcquisitionError("Failed to obtain access token", detail = {cause: token});
    }
    log:printInfo("Successfully obtained access token", agentId = auth.agentId, toolName = toolName);
    return token;
}

isolated function getFlowId(AuthConfig auth, string baseUrl, string|string[] scope, Pkce? pkce) returns error|AuthResponse {
    log:printInfo("Requesting flow id and authenticator id for token acquisition", agentId = auth.agentId, scope = scope);
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
    string authorizeUrl = baseUrl.concat(AUTHORIZE);
    http:Client httpclient = check new (authorizeUrl);
    http:Response res = check httpclient->post(EMPTY_STRING, req);
    json outputRes = check res.getJsonPayload();
    
    AuthResponse resp = check outputRes.cloneWithType(AuthResponse);
    return resp;
}

isolated function getCode(AuthResponse authResponse, AuthConfig auth, string baseUrl) returns error|string {
    log:printInfo("Requesting authorization code for token acquisition", agentId = auth.agentId);
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

    http:Client httpclient = check new (baseUrl.concat(AUTHN_HEADER));
    http:Response res =  check httpclient->post(EMPTY_STRING, req);
    json resp = check res.getJsonPayload();
    map<json> obj = check resp.ensureType();
    map<json> authData = check obj["authData"].ensureType();
    return authData[CODE].toString();
}

isolated function getToken(string code, AuthConfig auth, string baseUrl, Pkce? pkce) returns error|Token {
    log:printInfo("Requesting access token for token acquisition", agentId = auth.agentId);
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
    string output;
    foreach var [k, v] in formData.entries() {
       string encoded = check url:encode(v.toString(), UTF8_ENCODING);
       messageParams.push(string `${k}=${encoded}`);
    }
    output = strings:'join(AMPERSAND, ...messageParams);

    http:Request req = new;
    req.setHeader("Content-Type", APPLICATION_X_WWW_FORM_URLENCODED);
    req.setPayload(output);

    http:Client httpclient = check new (baseUrl.concat(TOKEN));
    http:Response res = check httpclient->post(EMPTY_STRING, req);
    json outputRes = check res.getJsonPayload();
    Token resp = check outputRes.cloneWithType(Token);
    return resp;
}

isolated function addToken(string toolName, Token token, cache:Cache tokenManager) returns string[] {
    TokenCache tokenDetail = new ();
    string[] scopes= tokenDetail.update(token);
    cache:Error? output = tokenManager.put(toolName, tokenDetail);
    if output is cache:Error {
       log:printError("Failed to store token in cache", output, toolName = toolName);
    }
    return scopes;
}

isolated function validateToken(AuthConfig auth, string baseUrl, string accessToken, 
                                string tokenTypeHint) returns error|ValidationResponse {
    Jwt|Introspection validation =  auth.tokenValidation;
    if validation is Jwt {
        validation = <Jwt>validation;
        record {string url;}? jwks = validation?.jwksConfig;
        if (jwks is record {string url;}) {
            return usingJwks(accessToken, jwks.url, auth);
        } else {
            string|crypto:PublicKey? certFile = validation?.certFile;
            if (certFile is string|crypto:PublicKey) {
                return usingCertificate(accessToken,certFile);
            }
        } 
    } else {
        string? url = validation.introspectionUrl;
        string introspectUrl = url is string ? url : baseUrl.concat(INTROSPECT);
        return usingIntrospection(introspectUrl, accessToken, auth.agentId, validation.clientConfig, tokenTypeHint);
    } 
    return error TokenValidationError("No valid token validation configuration found");   
}

isolated function usingJwks(string token, string url, AuthConfig auth) returns error|ValidationResponse {
    log:printInfo("Validating token using JWKS", agentId = auth.agentId);
    jwt:ValidatorConfig validatorConfig = {
        signatureConfig: {
            jwksConfig: {
                url: url
            }
        }
    };
    jwt:Payload result = check jwt:validate(token, validatorConfig);
    ValidationResponse resp = check result.cloneWithType(ValidationResponse);
    return resp;
}

isolated function usingCertificate(string token, string|crypto:PublicKey certificate) returns error|ValidationResponse {
    jwt:ValidatorConfig validatorConfig = {
        signatureConfig: {
            certFile: certificate
        }
    };
    jwt:Payload result = check jwt:validate(token, validatorConfig);
    ValidationResponse resp = check result.cloneWithType(ValidationResponse);
    return resp;
}

isolated function usingIntrospection(string url, string accessToken, string agentId, ClientCredentialsConfig clientConfig, 
                                     string? tokenTypeHint) returns ValidationResponse|error {
    log:printInfo("Validating token using introspection", agentId =agentId);
    string textPayload = TOKEN_WITH_EQUAL + accessToken;
    if tokenTypeHint is string {
        textPayload += TOKEN_TYPE_HINT + tokenTypeHint;
    }
    http:Client httpclient = check new (url, auth = {username: clientConfig.clientId, password: clientConfig.clientSecret});
    http:Request req = new;
    req.setHeader(CONTENT_TYPE_HEADER, APPLICATION_X_WWW_FORM_URLENCODED);
    req.setPayload(textPayload);
    http:Response res = check httpclient->post(EMPTY_STRING, req);
    json outputRes = check res.getJsonPayload();
    ValidationResponse resp = check outputRes.cloneWithType(ValidationResponse);
    return resp;
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

isolated function generatePKCE() returns Pkce? {
    string|error verifier = generateVerifier(64);
    if verifier is string {
        byte[] hash = crypto:hashSha256(verifier.toBytes());
        string challenge = base64UrlEncode(hash);
        return {
            verifier: verifier,
            challenge: challenge
        };
    }
    return;
}

# Represents a thread-safe cache for storing and managing an OAuth access token, its expiry time,
# and associated scopes.
isolated class TokenCache {

    private string accessToken;
    private int expTime;
    private string[] scopes;

    # Initializes the token cache with default empty values.
    isolated function init() {
       self.accessToken = EMPTY_STRING;
       self.expTime = -1;
       self.scopes = [];
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
            if currentTime[0] < self.expTime {
                return false;
            }
            return true;
       }
    }

    # Updates the cache using the token response and applies a clock skew to the expiry time.
    #
    # + token - The token response object received from the authorization server
    # + clockSkew - The clock skew in seconds to subtract from the token expiry time (default is 10 seconds)
    # + return - A cloned array of scopes extracted from the updated token
    isolated function update(Token token, decimal clockSkew = 10) returns string[]{
       lock {
            self.accessToken = token.access_token;
            self.expTime = token.expires_in - <int>clockSkew;
            string? scope = token?.scope;
            self.scopes = scope is string ? re ` `.split(scope) : [];
            return self.scopes.clone();
       }
    }
}
