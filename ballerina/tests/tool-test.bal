import ballerina/test;

@test:Config {}
function testResolveSchema() {

    ObjectInputSchema inputSchema = {
        'type: OBJECT,
        required: ["queryParams", "path"],
        properties: {
            path: {
                'const: "customsearch/v1"
            },
            queryParams: {
                'type: OBJECT,
                properties: {
                    q: {
                        'type: STRING,
                        default: "AIzaSyAYFLQpxzp5XlQGkAR8URuBJGr9YiiZyIU"
                    },
                    cx: {
                        'type: STRING,
                        default: "d60e6379e9234405a"
                    },
                    key: {
                        'type: STRING,
                        description: "the search query"

                    }
                }
            }
        }
    };

    map<json>|json[]? resolvedSchema = resolveSchema(inputSchema);

    if resolvedSchema !is map<json> {
        test:assertFail("resolveSchema output is not a map<json>");
    }

    test:assertEquals(resolvedSchema, {
                                          path: "customsearch/v1",
                                          queryParams: {
                                              q: "AIzaSyAYFLQpxzp5XlQGkAR8URuBJGr9YiiZyIU",
                                              cx: "d60e6379e9234405a"
                                          }
                                      });

    test:assertEquals(inputSchema, {
                                       'type: OBJECT,
                                       required: ["queryParams"],
                                       properties: {
                                           queryParams: {
                                               'type: OBJECT,
                                               properties: {
                                                   q: {
                                                       'type: STRING,
                                                       default: "AIzaSyAYFLQpxzp5XlQGkAR8URuBJGr9YiiZyIU"
                                                   },
                                                   cx: {
                                                       'type: STRING,
                                                       default: "d60e6379e9234405a"
                                                   },
                                                   key: {
                                                       'type: STRING,
                                                       description: "the search query"

                                                   }
                                               }
                                           }
                                       }
                                   });

}

@test:Config {}
function testExecuteSuccessfulOutput() returns error? {
    ToolConfig sendEmailTool = {
        name: "Send mail",
        description: "useful to send emails to a given recipient",
        parameters: {
            properties: {
                'input: {
                    properties: {
                        senderEmail: {'const: "ballerina@email.com"},
                        messageRequest: {
                            properties: {
                                to: {
                                    items: {'type: STRING}
                                },
                                subject: {'type: STRING},
                                body: {
                                    'type: STRING,
                                    format: "text/html"
                                }
                            }
                        }
                    }
                }
            }
        },
        caller: sendMail
    };
    LlmToolResponse sendMailInput = {
        name: "Send_mail",
        arguments: {
            input: {
                senderEmail: "ballerina@email.com",
                messageRequest: {
                    to: ["alica@wso2.com"],
                    subject: "Greetings Alica!",
                    body: "<h1>Hi Alica</h1><p>Welcome to ai module Alica</p>"
                }
            }
        }
    };
    ToolStore toolStore = check new (sendEmailTool);
    ToolOutput output = check toolStore.execute(sendMailInput);
    if output.value is error {
        test:assertFail("tool execution output is an error");
    }
}

@test:Config {}
function testExecuteErrorOutput() returns error? {
    ToolConfig sendEmailTool = {
        name: "Send mail",
        description: "useful to send emails to a given recipient",
        parameters: {
            properties: {
                'input: {
                    properties: {
                        senderEmail: {'const: "test@email.com"},
                        messageRequest: {
                            properties: {
                                to: {
                                    items: {'type: STRING}
                                },
                                subject: {'type: STRING},
                                body: {
                                    'type: STRING,
                                    format: "text/html"
                                }
                            }
                        }
                    }
                }
            }
        },
        caller: sendMail
    };
    LlmToolResponse sendMailInput = {
        name: "Send_mail",
        arguments: {
            input: {
                messageRequest: {
                    to: ["alica@wso2.com"],
                    subject: "Greetings Alica!",
                    body: "<h1>Hi Alica</h1><p>Welcome to ai module Alica</p>"
                }
            }
        }
    };
    ToolStore toolStore = check new (sendEmailTool);
    ToolOutput output = check toolStore.execute(sendMailInput);
    if output.value !is error {
        test:assertFail("tool execution output is not an error");
    }
}

@test:Config {}
function testExecutionError() returns error? {
    ToolConfig sendEmailTool = {
        name: "Send mail",
        description: "useful to send emails to a given recipient",
        parameters: {
            properties: {
                'input: {
                    properties: {
                        senderEmail: {'const: "ballerina@email.com"},
                        messageRequest: {
                            properties: {
                                to: {
                                    items: {'type: STRING}
                                },
                                subject: {'type: STRING},
                                body: {
                                    'type: STRING,
                                    format: "text/html"
                                }
                            }
                        }
                    }
                }
            }
        },
        caller: sendMail
    };
    LlmToolResponse sendMailInput = {
        name: "Send_mail",
        arguments: {
            input: {
                messageRequest: {
                    to: "alica@wso2.com", // errornous generation
                    subject: "Greetings Alica!",
                    body: "<h1>Hi Alica</h1><p>Welcome to ai module Alica</p>"
                }
            }
        }
    };
    ToolStore toolStore = check new (sendEmailTool);
    ToolOutput output = check toolStore.execute(sendMailInput);
    if output.value !is error {
        test:assertFail("tool execution should return an error, yet it is succesfull");
    }
}

@test:Config {}
function testToolWithDefaultParameters() returns error? {
    ToolConfig testToolConfig = {
        name: "testTool",
        description: "testTool",
        parameters: {
            properties: {
                a: {'type: STRING},
                b: {'type: STRING},
                c: {'type: STRING}
            },
            required: ["a"]
        },
        caller: testTool
    };
    LlmToolResponse testToolInput = {
        name: "testTool",
        arguments: {
            a: "required",
            c: "override"
        }
    };
    ToolStore toolStore = check new (testToolConfig);
    ToolOutput output = check toolStore.execute(testToolInput);
    test:assertEquals(output.value, "required default-one override");
}

@test:Config {}
function testExecutionPanicError() returns error? {
    ToolConfig sendEmailTool = {
        name: "testToolPanic",
        description: "testToolPanic",
        parameters: {
            properties: {
                data: {'type: STRING}
            },
            required: ["data"]
        },
        caller: testToolPanic
    };
    LlmToolResponse sendMailInput = {
        name: "testToolPanic",
        arguments: {
            input: {
                messageRequest: {
                    data: "test"
                }
            }
        }
    };
    ToolStore toolStore = check new (sendEmailTool);
    ToolOutput|Error output = toolStore.execute(sendMailInput);
    if output !is Error {
        test:assertFail("tool execution should failed with erronous generation, yet it is succesfull");
    }
}

@test:Config
isolated function testInitializingToolStoreWithoutNoTools() returns error? {
    ToolStore toolStore = check new ();
    test:assertEquals(toolStore.tools.toArray().length(), 0);
}

@test:Config {}
function testDuplicateFunctionToolNameError() returns error? {
    ToolStore|error toolStore = new (duplicateToolOne, duplicateToolTwo);
    test:assertTrue(toolStore is error);
    if toolStore is error {
        test:assertEquals(toolStore.message(),
            "duplicate tool name found: 'duplicateTool'. " +
            "Tool names must be unique across all tools and toolkits registered with the agent");
    }
}

@test:Config {}
function testDuplicateToolConfigNameError() returns error? {
    ToolConfig tool1 = {name: "duplicateConfigTool", description: "d1", caller: testTool};
    ToolConfig tool2 = {name: "duplicateConfigTool", description: "d2", caller: testTool};
    ToolStore|error toolStore = new (tool1, tool2);
    test:assertTrue(toolStore is error);
    if toolStore is error {
        test:assertEquals(toolStore.message(),
            "duplicate tool name found: 'duplicateConfigTool'. " +
            "Tool names must be unique across all tools and toolkits registered with the agent");
    }
}

@test:Config {}
function testUniqueToolNamesAcrossMixedSourcesSucceeds() returns error? {
    ToolConfig configTool = {name: "configTool", description: "a tool config", caller: testTool};
    ToolStore toolStore = check new (configTool, duplicateToolOne);
    test:assertEquals(toolStore.tools.length(), 2);
}

@test:Config {
    groups: ["mcp"]
}
function testDuplicateNameBetweenMcpToolkitAndStandaloneTool() returns error? {
    McpToolKit mcpToolKit = check new (serverUrl = "http://localhost:3000/mcp", info = {name: "Greeting", version: ""});
    ToolConfig duplicateTool = {
        name: "single-greeting",
        description: "collides with the mcp toolkit's tool name",
        caller: testTool
    };
    ToolStore|error toolStore = new (mcpToolKit, duplicateTool);
    test:assertTrue(toolStore is error);
    if toolStore is error {
        test:assertEquals(toolStore.message(),
            "duplicate tool name found: 'single-greeting'. " +
            "Tool names must be unique across all tools and toolkits registered with the agent");
    }
}

@test:Config {
    groups: ["mcp"]
}
function testMcpToolMetadataTracking() returns error? {
    McpToolKit mcpToolKit = check new (serverUrl = "http://localhost:3000/mcp", info = {name: "Greeting", version: ""});
    ToolConfig regularTool = {
        name: "regularTool",
        description: "a non-mcp tool",
        caller: testTool
    };
    ToolStore toolStore = check new (mcpToolKit, regularTool);

    test:assertTrue(toolStore.isMcpTool("single-greeting"));
    test:assertTrue(toolStore.getToolKitName("single-greeting").toString().includes("McpToolKit"));

    test:assertFalse(toolStore.isMcpTool("regularTool"));
}

isolated class DottedNameMcpToolKit {
    *McpBaseToolKit;

    public isolated function getTools() returns ToolConfig[] {
        return [
            {
                name: "admin.tools.list",
                description: "an mcp tool whose name contains dots, which are valid per the MCP spec",
                caller: testTool
            }
        ];
    }
}

@test:Config
isolated function testMcpToolMetadataTrackingUsesSanitizedName() returns error? {
    DottedNameMcpToolKit dottedNameMcpToolKit = new;
    ToolStore toolStore = check new (dottedNameMcpToolKit);

    // Tool names are sanitized (dots replaced with underscores) during registration, so the
    // toolkit/mcp metadata maps must be keyed by the sanitized name to stay consistent with
    // the tool name the LLM is actually given.
    test:assertTrue(toolStore.tools.hasKey("admin_tools_list"));
    test:assertTrue(toolStore.isMcpTool("admin_tools_list"));
    test:assertTrue(toolStore.getToolKitName("admin_tools_list").toString().includes("DottedNameMcpToolKit"));

    test:assertFalse(toolStore.isMcpTool("admin.tools.list"));
    test:assertEquals(toolStore.getToolKitName("admin.tools.list"), ());
}

@test:Config
isolated function testToolExecutionWithEmptyQueryRecordParam() returns error? {
    HttpTool httpGet =
        {
        name: "httpGet",
        path: "/example-get",
        method: GET,
        description: "test HTTP GET tool",
        parameters: {
            "location": {
                description: "location to get",
                location: QUERY,
                required: true,
                schema: {
                    'type: OBJECT,
                    properties: {
                        "street": {
                            'type: STRING,
                            description: "location to get"
                        },
                        "city": {
                            'type: STRING,
                            description: "location to get"
                        }
                    }
                }
            }
        }
    };
    map<json> parameters = {
        "name": "httpGet",
        "arguments": {
            "httpInput": {
                "parameters": {
                    "location": {}
                }
            }
        }
    };
    string _ = check getParamEncodedPath(httpGet, parameters);
}
