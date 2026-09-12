import ballerina/http;
import ballerina/test;

http:Client testClient = check new ("http://localhost:9091");

@test:Config {}
function testGetAssets() returns error? {
    http:Response response = check testClient->/assets;
    test:assertEquals(response.statusCode, 200);
}

@test:Config {}
function testGetInstitutions() returns error? {
    http:Response response = check testClient->/institutions;
    test:assertEquals(response.statusCode, 200);
}