import ballerina/test;

@test:BeforeEach
function resetOrderRepository() {
    clearOrders();
}

function sampleOrderRequest() returns OrderCreateRequest => {
    orderId: "ORD-001",
    customerId: "CUS-001",
    restaurantId: "RES-001",
    deliveryAddressId: "ADDR-001",
    items: [{menuItemId: "ITEM-001", itemName: "Kapana Plate", quantity: 2, unitPrice: 75.00}],
    totalAmount: 150.00,
    createdAt: "2026-08-17T12:00:00Z"
};

@test:Config
function testCompleteOrderLifecycle() returns error? {
    FoodOrder foodOrder = check createOrder(sampleOrderRequest());
    test:assertEquals(foodOrder.status, CREATED);
    OrderStatus[] lifecycle = [CONFIRMED, PREPARING, READY, OUT_FOR_DELIVERY, DELIVERED];
    foreach OrderStatus nextStatus in lifecycle {
        foodOrder = check transitionOrder("ORD-001", {
                                                         status: nextStatus,
                                                         occurredAt: "2026-08-17T12:30:00Z"
                                                     });
    }
    test:assertEquals(foodOrder.status, DELIVERED);
}

@test:Config
function testInvalidTransitionIsRejected() returns error? {
    _ = check createOrder(sampleOrderRequest());
    FoodOrder|error result = transitionOrder("ORD-001", {
                                                            status: READY,
                                                            occurredAt: "2026-08-17T12:05:00Z"
                                                        });
    test:assertTrue(result is error);
}

@test:Config
function testCancellationAfterReadyIsRejected() returns error? {
    _ = check createOrder(sampleOrderRequest());
    _ = check transitionOrder("ORD-001", {status: CONFIRMED, occurredAt: "2026-08-17T12:05:00Z"});
    _ = check transitionOrder("ORD-001", {status: PREPARING, occurredAt: "2026-08-17T12:10:00Z"});
    _ = check transitionOrder("ORD-001", {status: READY, occurredAt: "2026-08-17T12:20:00Z"});
    FoodOrder|error result = transitionOrder("ORD-001", {
                                                            status: CANCELLED,
                                                            occurredAt: "2026-08-17T12:21:00Z"
                                                        });
    test:assertTrue(result is error);
}
