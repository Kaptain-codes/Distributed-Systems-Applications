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
    json|error response = testClient->/'order/health;
    test:assertEquals(response, {status: "UP", 'service: "order"});
}

// Negative test function
@test:Config {}
function testServiceWithEmptyName() returns error? {
    http:Response response = check testClient->/'order/health;
    test:assertEquals(response.statusCode, 200);
    json healthPayload = check response.getJsonPayload();
    test:assertEquals(healthPayload, {status: "UP", 'service: "order"});
}

@test:Config {}
function testTransientRetryBackoffSchedule() {
    test:assertEquals(retryBackoffSeconds(2), <decimal>1.0);
    test:assertEquals(retryBackoffSeconds(3), <decimal>5.0);
}

@test:Config {}
function testDerivedEventIdIsStableForTheSameSource() {
    string first = checkpanic derivedEventId("source-1", "orders.ready");
    string second = checkpanic derivedEventId("source-1", "orders.ready");
    string differentTarget = checkpanic derivedEventId("source-1", "payment.requested");
    test:assertEquals(first, second);
    test:assertNotEquals(first, differentTarget);
}

@test:Config {}
function testAtomicTransitionAppendsOneStatusHistoryEntryInMemory() {
    Order current = {
        orderId: "order-1", customerId: "customer-1", restaurantId: "restaurant-1",
        items: [], total: 0, deliveryAddress: "address", pickupAddress: "pickup",
        paymentMethod: "CARD", createdAt: "now", updatedAt: "now",
        status: "PREPARING", version: 2
    };
    Order proposed = transition(current, "READY");
    Order|error result = applyAtomicTransition(current, proposed);
    test:assertTrue(result is Order);
    if result is Order {
        test:assertEquals(result.version, 3);
        test:assertEquals(result.statusHistory.length(), 1);
        json firstHistory = result.statusHistory[0];
        test:assertEquals(firstHistory, {status: "READY", changedAt: result.updatedAt});
    }
}

@test:Config {}
function testMissingMongoIdDoesNotPanic() {
    json invalid = {status: "READY"};
    Order|error restored = restoreMongoOrder(invalid);
    test:assertTrue(restored is error);
}

@test:Config {}
function testCancellationStateRules() {
    Order created = testOrder("CREATED");
    Order confirmed = testOrder("CONFIRMED");
    Order preparing = testOrder("PREPARING");
    test:assertTrue(canCancel(created));
    test:assertTrue(canCancel(confirmed));
    test:assertFalse(canCancel(preparing));
}

function testOrder(string status) returns Order {
    return {
        orderId: "cancel-test-" + status, customerId: "customer-1",
        restaurantId: "restaurant-1", items: [], total: 0,
        deliveryAddress: "address", pickupAddress: "pickup",
        paymentMethod: "CARD", createdAt: "now", updatedAt: "now",
        status: status, version: 1
    };
}

// After Suite Function
@test:AfterSuite
function afterSuiteFunc() {
    io:println("I'm the after suite function!");
}
