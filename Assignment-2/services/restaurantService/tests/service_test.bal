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
    json|error response = testClient->/restaurant/health;
    test:assertEquals(response, {status: "UP", 'service: "restaurant"});
}

// Negative test function
@test:Config {}
function testServiceWithEmptyName() returns error? {
    http:Response response = check testClient->/restaurant/health;
    test:assertEquals(response.statusCode, 200);
    json healthPayload = check response.getJsonPayload();
    test:assertEquals(healthPayload, {status: "UP", 'service: "restaurant"});
}

@test:Config {}
function testStockValidationRejectsUnavailableItems() {
    MenuItem item = {id: "item-test", restaurantId: "res-test", name: "Meal",
        unitPrice: 10.0, available: false, stockQty: 2};
    menuItems[item.id] = item;
    KitchenOrder kitchenOrder = {id: "order-test", restaurantId: "res-test",
        items: [{menuItemId: item.id, quantity: 1}], status: "PENDING_DECISION"};
    test:assertFalse(inStock(kitchenOrder));
    _ = menuItems.remove(item.id);
}

// After Suite Function
@test:AfterSuite
function afterSuiteFunc() {
    io:println("I'm the after suite function!");
}
