import ballerina/http;
import ballerina/test;

// =========================================================
// Task 3 API Tests
// =========================================================

string testAssetTag = "TEST-ASSET-001";

// Test 1: Create an Asset
@test:Config {}
function testCreateAsset() returns error? {

    Asset asset = {
        assetTag: testAssetTag,
        name: "Test Laptop",
        description: "Laptop created for automated API testing",
        institutionId: "NUST",
        site: "Windhoek",
        dateAcquired: "2026-09-14",
        status: AVAILABLE
    };

    http:Response response = check testClient->post("/assets", asset);

    test:assertEquals(
        response.statusCode,
        201,
        "Expected asset creation to return HTTP 201"
    );
}


// Test 2: Get an Asset by Asset Tag
@test:Config {}
function testGetAssetByAssetTag() returns error? {

    http:Response response = check testClient->get(
        "/assets/" + testAssetTag
    );

    test:assertEquals(
        response.statusCode,
        200,
        "Expected fetching an existing asset to return HTTP 200"
    );

    json payload = check response.getJsonPayload();

    test:assertEquals(
        payload.assetTag,
        testAssetTag,
        "Returned asset tag does not match the requested asset tag"
    );
}


// Test 3: Get All Assets
@test:Config {}
function testGetAllAssets() returns error? {

    http:Response response = check testClient->get("/assets");

    test:assertEquals(
        response.statusCode,
        200,
        "Expected listing all assets to return HTTP 200"
    );

    json payload = check response.getJsonPayload();

    test:assertTrue(
        payload is json[],
        "Expected the response to contain an array of assets"
    );
}


// Test 4: Get Assets by Institution
@test:Config {}
function testGetAssetsByInstitution() returns error? {

    http:Response response = check testClient->get(
        "/assets/institute/NUST"
    );

    test:assertEquals(
        response.statusCode,
        200,
        "Expected institution filtering to return HTTP 200"
    );

    json payload = check response.getJsonPayload();

    test:assertTrue(
        payload is json[],
        "Expected the institution filter to return an array of assets"
    );
}


// Test 5: Get Overdue Assets
@test:Config {}
function testGetOverdueAssets() returns error? {

    http:Response response = check testClient->get(
        "/assets/overdue"
    );

    test:assertEquals(
        response.statusCode,
        200,
        "Expected overdue asset request to return HTTP 200"
    );

    json payload = check response.getJsonPayload();

    test:assertTrue(
        payload is json[],
        "Expected overdue assets response to contain an array"
    );
}


// Test 6: Negative Test - Asset Does Not Exist
@test:Config {}
function testGetNonExistingAsset() returns error? {

    string nonExistingAssetTag = "DOES-NOT-EXIST-999";

    http:Response response = check testClient->get(
        "/assets/" + nonExistingAssetTag
    );

    test:assertEquals(
        response.statusCode,
        404,
        "Expected a non-existing asset to return HTTP 404"
    );
}
