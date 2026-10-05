import ballerina/io;
import ballerina/http;
import ballerina/test;

http:Client testClient = check new ("http://localhost:9090");

// Before Suite Function
@test:BeforeSuite
function beforeSuiteFunc() {
    io:println("I'm the before suite function!");
}

// Test function
@test:Config {}
function testServiceWithProperName() {
    json|error response = testClient->/payment/health;
    test:assertEquals(response, {status: "UP", 'service: "payment"});
}

// Negative test function
@test:Config {}
function testServiceWithEmptyName() returns error? {
    http:Response response = check testClient->/payment/health;
    test:assertEquals(response.statusCode, 200);
    json healthPayload = check response.getJsonPayload();
    test:assertEquals(healthPayload, {status: "UP", 'service: "payment"});
}

@test:Config {}
function testPaymentLookupReturnsCommonNotFoundError() returns error? {
    http:Response response = check testClient->get("/payment/missing-payment");
    test:assertEquals(response.statusCode, 404);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload, {'error: "NOT_FOUND", message: "payment was not found"});
}

// After Suite Function
@test:AfterSuite
function afterSuiteFunc() {
    io:println("I'm the after suite function!");
}
