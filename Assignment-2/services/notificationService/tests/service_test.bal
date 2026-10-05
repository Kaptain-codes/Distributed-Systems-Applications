import ballerina/http;
import ballerina/test;

http:Client testClient = check new ("http://localhost:9090");

@test:Config {}
function testHealthReturnsUp() {
    json|error response = testClient->/notification/health;
    test:assertEquals(response, {status: "UP", 'service: "notification"});
}

@test:Config {}
function testHealthReturnsStatus200() returns error? {
    http:Response response = check testClient->/notification/health;
    test:assertEquals(response.statusCode, 200);
    json healthPayload = check response.getJsonPayload();
    test:assertEquals(healthPayload, {status: "UP", 'service: "notification"});
}
