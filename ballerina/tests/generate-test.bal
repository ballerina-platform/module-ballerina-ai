import ballerina/test;

@test:Config {enable: false}
function testGenerateFunction() returns error? {
    MockLLM mockLlm = new ();
    int result = check mockLlm.generate(`What is 1 + 1?`);
    test:assertEquals(result, 2);

    string resultStr = check mockLlm.generate(`What is 1 + 1?`);
    test:assertEquals(resultStr, "2j");
}
