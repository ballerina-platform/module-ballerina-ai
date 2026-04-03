import ballerina/ai;
import ballerina/http;
import ballerina/jwt;
import ballerina/test;
import ballerina/time;
import ballerina/uuid;

map<string> authCodeStore = {};
map<string> tokenStore = {};
map<string> agentSessionStore = {};
map<string> flowStore = {};
map<string> codeStore = {};

const VALID_CLIENT_SECRET = "secret123";
const VALID_CLIENT_ID = "client123";
const VALID_USERNAME = "admin";
const VALID_PASSWORD = "admin";
const KEYSTORE_PATH = "resources/keystore/ballerinaKeystore.p12";
string scope = "";

service /oauth2 on new http:Listener(8094) {
    resource function post authn(@http:Payload json payload) returns http:Found|http:BadRequest|error {
        string flowId = check payload.flowId;
        if !flowStore.hasKey(flowId) {
            return <http:BadRequest>{body: "invalid_flow"};
        }

        string username = check payload.selectedAuthenticator.params.username;
        string password = check payload.selectedAuthenticator.params.password;

        if username != VALID_USERNAME || password != VALID_PASSWORD {
            return <http:BadRequest>{body: "invalid_credentials"};
        }

        string code = uuid:createType1AsString();
        authCodeStore[code] = "default";
        return <http:Found>{
            body: {
                authData: {
                    code: code,
                    state: "logpg",
                    session_state: uuid:createType1AsString()
                }
            }
        };
    }

    resource function post authorize(http:Request req) returns http:Found|http:BadRequest|http:Unauthorized|error {
        map<string|string[]> form = check req.getFormParams();
        string clientId = form["client_id"].toString();
        scope = form["scope"].toString();

        if clientId != VALID_CLIENT_ID {
            return <http:BadRequest>{body: "invalid_client"};
        }

        string flowId = uuid:createType1AsString();
        flowStore[flowId] = "PENDING";

        return <http:Found>{
            body: {
                flowId,
                flowStatus: "INCOMPLETE",
                flowType: "AUTHENTICATION",
                nextStep: {
                    stepType: "AUTHENTICATOR_PROMPT",
                    authenticators: [
                        {
                            authenticatorId: "QmFzaWNBdXRoZW50aWNhdG9yOkxPQ0FM",
                            authenticator: "Username & Password"
                        }
                    ]
                }
            }
        };
    }

    resource function post token(http:Request req) returns http:Found|http:BadRequest|error {
        map<string|string[]> form = check req.getFormParams();
        string grantType = form["grant_type"].toString();
        string clientId = form["client_id"].toString();
        string code = form["code"].toString();

        if clientId != VALID_CLIENT_ID {
            return <http:BadRequest>{body: "invalid_client"};
        }

        if grantType != "authorization_code" {
            return <http:BadRequest>{body: "unsupported_grant"};
        }

        if !authCodeStore.hasKey(code) {
            return <http:BadRequest>{body: "invalid_code"};
        }
        jwt:IssuerConfig payload = {
            username: "agent-user",
            issuer: "mock-is",
            audience: "booking_api",
            customClaims: {scope: scope},
            expTime: <decimal>(time:utcNow()[0] + 3600),
            signatureConfig: {
                config: {
                    keyStore: {
                        path: KEYSTORE_PATH,
                        password: "ballerina"
                    },
                    keyAlias: "ballerina",
                    keyPassword: "ballerina"
                }
            }
        };

        string accessToken = check jwt:issue(payload);
        return <http:Found>{
            body: {
                access_token: accessToken,
                token_type: "Bearer",
                expires_in: 3600
            }
        };
    }

}

service /llm on new http:Listener(9096) {

    resource function post chat/completions(@http:Payload json payload) returns json|error {
        json[] messages = check payload.messages.ensureType();
        json last = messages[messages.length() - 1];
        string role = check last.role.ensureType();

        if role == "user" {
            string text = check last.content.ensureType();
            string functionName = "listTasks";
            json args = {};

            if text.includes("pay") || text.includes("meet") {
                functionName = "addTask";
                args = {
                    description: text,
                    dueBy: {
                        year: 2026,
                        month: 3,
                        day: 28
                    }
                };
            } else if text.includes("date") {
                functionName = "getCurrentDate";
            }
            json chatCompletionResponse = {
                role: "assistant",
                content: (),
                function_call: {name: functionName, arguments: args.toJsonString()}
            };
            return buildAgentIdentityCompletionResponse(chatCompletionResponse);
        }

        if role == "function" {
            string fnName = check last.name.ensureType();
            string msg = "Operation completed.";
            if fnName == "addTask" {
                msg = "Task added successfully.";
            } else if fnName == "listTasks" {
                msg = "Here are your current tasks.";
            } else if fnName == "getCurrentDate" {
                msg = "Retrieved today’s date successfully.";
            }
            return buildAgentIdentityCompletionResponse({role: "assistant", content: msg});
        }
        return error("Unsupported role");
    }
}

isolated function buildAgentIdentityCompletionResponse(json message) returns json => {
    id: "mock-id",
    'object: "chat.completion",
    created: 1700000000,
    model: "mock-gpt",
    choices: [{index: 0, message, finish_reason: "function_call"}],
    usage: {prompt_tokens: 5, completion_tokens: 10, total_tokens: 15}
};

final ai:Wso2ModelProvider taskAssistantAgentModel = check new ("http://localhost:9096/llm", API_KEY);

type Task record {|
    string description;
    time:Date dueBy?;
    time:Date createdAt = time:utcToCivil(time:utcNow());
    time:Date completedAt?;
    boolean completed = false;
|};

isolated map<Task> tasks = {
    "a2af0faa-3b73-4184-9be1-87b29a963be6": {
        description: "Buy groceries",
        dueBy: time:utcToCivil(time:utcAddSeconds(time:utcNow(), 60 * 5))
    }
};

@ai:AgentTool {
    auth: {
        clientId: "client123",
        clientSecret: "secret123",
        redirectUri: "http://localhost:8000/callback",
        baseAuthUrl: "http://localhost:8094/oauth2",
        scopes: "add"
    }
}
isolated function addTask(string description, time:Date? dueBy) returns error? {
    lock {
        tasks[uuid:createRandomUuid()] = {description, dueBy: dueBy.clone()};
    }
}

@ai:AgentTool {
    auth: {
        clientId: "client123",
        clientSecret: "secret123",
        redirectUri: "http://localhost:8000/callback",
        baseAuthUrl: "http://localhost:8094/oauth2",
        scopes: "list"
    }
}
isolated function listTasks() returns Task[] {
    lock {
        return tasks.toArray().clone();
    }
}

@ai:AgentTool {
    auth: {
        clientId: "client123",
        clientSecret: "secret123",
        redirectUri: "http://localhost:8000/callback",
        baseAuthUrl: "http://localhost:8094/oauth2",
        scopes: "get"
    }
}
isolated function getCurrentDate() returns time:Date {
    time:Civil {year, month, day} = time:utcToCivil(time:utcNow());
    return {year, month, day};
}

final ai:Agent taskAssistantAgent = check new (
    systemPrompt = {
        role: "Task Assistant",
        instructions: string `You are a helpful assistant for 
            managing a to-do list. You can manage tasks and
            help a user plan their schedule.`
    },
    model = taskAssistantAgentModel,
    tools = [addTask, listTasks, getCurrentDate],
    credential = {
        id: "admin",
        secret: "admin"
    }
);

@test:Config {
    groups: ["agent-identity"]
}
function testAgentIdentityLocalAddTool() returns error? {
    string result = check taskAssistantAgent.run("I have to pay my WiFi bill by " +
        "tomorrow and meet Jane for tea at 4pm on the 28th.");
    test:assertTrue(result.includes("Task added successfully"));
}

@test:Config {
    groups: ["agent-identity"]
}
function testAgentIdentityLocalListTool() returns error? {
    string result = check taskAssistantAgent.run("What do I have on my plate today?");
    test:assertTrue(result.includes("Here are your current tasks."));
}
