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

# Represents a tracing span for the creation and configuration of an agent's identity.
public isolated distinct class CreateAgentIdentitySpan {
   *AiSpan;
   private final BaseSpanImp baseSpan;

   # Initializes a new agent identity creation span.
   # 
   # + agentName - The descriptive name or role of the agent being created (e.g., "CustomerSupport")
   isolated function init(string agentName) {
      self.baseSpan = new (string `${CREATE_AGENT_IDENTITY} ${agentName}`);
      self.addTag(OPERATION_NAME, CREATE_AGENT_IDENTITY);
      self.addTag(PROVIDER_NAME, "Ballerina");
      self.addTag(AGENT_NAME, agentName);
   }

   # Records the unique agent identifier assigned by the identity system.
   # 
   # + agentId - The unique agent identifier (e.g., a UUID or system ID)
   public isolated function addId(string? agentId) {
      self.addTag(AGENT_ID, agentId);
   }

   # Adds a custom tag to the span.
   # 
   # + key - The metadata tag name from `GenAiTagNames`
   # + value - The value to be recorded
   isolated function addTag(GenAiTagNames key, anydata value) {
      self.baseSpan.addTag(key, value);
   }

   # Closes the span and records the final execution status.
   #
   # + err - An optional error if the identity creation process failed   
   public isolated function close(error? err = ()) {
      self.baseSpan.close(err);
   }
}

# Represents a tracing span for the initial OIDC/OAuth2 authorization request.
public isolated distinct class InvokeAuthorizeEndpointSpan {
   *AiSpan;
   private final BaseSpanImp baseSpan;

   # Initializes a span for the authorization endpoint invocation.
   # 
   # + organization - The root organization handle or tenant name
   isolated function init(string organization) {
      self.baseSpan = new (string `${INVOKE_AUTHORIZE_ENDPOINT} ${organization}`);
      self.addTag(OPERATION_NAME, INVOKE_AUTHORIZE_ENDPOINT);
   }

   # Records the URL of the identity provider used for this agent.
   # 
   # + url - The base URL of the Identity Server
   public isolated function addProviderUrl(string url) {
      self.addTag(IDENTITY_PROVIDER_URL, url);
   }

   # Records parameters from the /authorize call including PKCE challenge.
   # 
   # + clientId - The OAuth2 client identifier
   # + scopes - The list of requested scopes
   # + url - The authorize endpoint URL of the Identity Server
   # + 'resource - The resource indicator (e.g., booking_api)
   # + challenge - The PKCE code_challenge
   public isolated function addAuthRequestDetails(string clientId, string[]|string? scopes, string url, 
         string 'resource = "", string? challenge = ()) {
      self.addTag(IDENTITY_PROVIDER_URL, url);
      self.addTag(CLIENT_ID, clientId);
      self.addTag(AUTH_SCOPES, scopes.toString());
      self.addTag(RESOURCE_INDICATOR, 'resource);
      if challenge is string {
         self.addTag(PKCE_CHALLENGE, challenge);
         self.addTag(PKCE_METHOD, "S256");
      }
   }

   isolated function addTag(GenAiTagNames key, anydata value) {
      self.baseSpan.addTag(key, value);
   }

   # Closes the span and records its final status.
   #
   # + err - Optional error that indicates if the operation failed   
   public isolated function close(error? err = ()) {
      self.baseSpan.close(err);
   }
}

# Represents a tracing span for an API-driven authentication flow.
public isolated distinct class AgentAuthenticationSpan {
   *AiSpan;
   private final BaseSpanImp baseSpan;

   # Initializes a span for the agent authentication process.
   # 
   # + flowId - The unique identifier for the authentication flow
   isolated function init(string flowId) {
      self.baseSpan = new (string `${AGENT_AUTHENTICATION} Flow: ${flowId}`);
      self.addTag(OPERATION_NAME, AGENT_AUTHENTICATION);
      self.addTag(FLOW_ID, flowId);
   }

   # Records the identity and authenticator used.
   # 
   # + agentId - The unique identifier of the agent
   # + authenticatorId - The ID of the authenticator (e.g., BasicAuth)
   public isolated function addAgentIdentity(string agentId, string authenticatorId) {
      self.addTag(AGENT_ID, agentId);
      self.addTag(AUTHENTICATOR_ID, authenticatorId);
   }

   isolated function addTag(GenAiTagNames key, anydata value) {
      self.baseSpan.addTag(key, value);
   }

   # Closes the span and records its final status.
   #
   # + err - Optional error that indicates if the operation failed   
   public isolated function close(error? err = ()) {
      self.baseSpan.close(err);
   }
}

# Represents a tracing span for exchanging an authorization code for an access token.
public isolated distinct class ExchangeTokenSpan {
   *AiSpan;
   private final BaseSpanImp baseSpan;

   # Initializes a span for the token exchange.
   isolated function init() {
      self.baseSpan = new (EXCHANGE_TOKEN);
      self.addTag(OPERATION_NAME, EXCHANGE_TOKEN);
   }

   # Records the details of the token exchange including PKCE verification.
   # 
   # + clientId - The OAuth2 client identifier
   public isolated function addExchangeDetails(string clientId) {
      self.addTag(CLIENT_ID, clientId);
   }

   isolated function addTag(GenAiTagNames key, anydata value) {
      self.baseSpan.addTag(key, value);
   }

   # Closes the span and records its final status.
   #
   # + err - Optional error that indicates if the operation failed   
   public isolated function close(error? err = ()) {
      self.baseSpan.close(err);
   }
}

# Represents a tracing span for validating an access token.
public isolated distinct class ValidateTokenSpan {
   *AiSpan;
   private final BaseSpanImp baseSpan;

   # Initializes a token validation span.
   # 
   # + provider - The Identity Server or Authority that issued/validates the token
   isolated function init(string provider) {
      self.baseSpan = new (string `${VALIDATE_TOKEN} from ${provider}`);
      self.addTag(OPERATION_NAME, VALIDATE_TOKEN);
      self.addTag(PROVIDER_NAME, provider);
   }

   # Records the result of the token validation.
   # 
   # + active - Whether the token is currently valid and not expired
   # + clientId - The client ID associated with the token
   # + subject - The agent or user identifier (sub claim)
   public isolated function addValidationResult(boolean? active, string? clientId = (), string? subject = ()) {
      string status = active is () ? "unknown" : (active ? "active" : "inactive");
      self.addTag(TOKEN_STATUS, status);
      if clientId is string { self.addTag(CLIENT_ID, clientId); }
      if subject is string { self.addTag(AGENT_ID, subject); }
   }

   isolated function addTag(GenAiTagNames key, anydata value) {
      self.baseSpan.addTag(key, value);
   }

   # Closes the span and records its final status.
   #
   # + err - Optional error that indicates if the operation failed   
   public isolated function close(error? err = ()) {
      self.baseSpan.close(err);
   }
}

# Represents a tracing span for validating agent permissions (scopes) for a tool.
public isolated distinct class ValidateToolAuthorizationSpan {
   *AiSpan;
   private final BaseSpanImp baseSpan;

   # Initializes a span for tool-level authorization validation.
   # 
   # + toolName - The name of the tool the agent is attempting to execute
   isolated function init(string toolName) {
      self.baseSpan = new (string `${VALIDATE_TOOL_AUTHORIZATION}: ${toolName}`);
      self.addTag(OPERATION_NAME, VALIDATE_TOOL_AUTHORIZATION);
      self.addTag(TOOL_NAME, toolName);
   }

   # Records the comparison between required and granted scopes.
   # 
   # + required - The scopes required to run the tool
   # + granted - The scopes present in the agent's current token
   public isolated function addScopeCheck(string[] required, string[] granted) {
      self.addTag(REQUIRED_SCOPES, required);
      self.addTag(GRANTED_SCOPES, granted);
   }

   isolated function addTag(GenAiTagNames key, anydata value) {
      self.baseSpan.addTag(key, value);
   }

   # Closes the span and records its final status.
   #
   # + err - Optional error that indicates if the operation failed   
   public isolated function close(error? err = ()) {
      self.baseSpan.close(err);
   }
}
