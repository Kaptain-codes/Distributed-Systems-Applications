import ballerina/test;

@test:BeforeEach
function resetDeliveryRepository() {
    clearDeliveryStore();
}

@test:Config
function testDriverIsReservedAndReleased() returns error? {
    _ = check registerDriver({
                                 driverId: "DRV-001",
                                 fullName: "Paulus Amutenya",
                                 phoneNumber: "+264811111111",
                                 vehicleRegistration: "N12345W"
                             });
    _ = check assignDelivery({
                                 deliveryId: "DEL-001",
                                 orderId: "ORD-001",
                                 driverId: "DRV-001",
                                 restaurantAddress: "Central Windhoek",
                                 customerAddress: "Klein Windhoek",
                                 assignedAt: "2026-08-17T12:00:00Z"
                             });
    test:assertEquals((check listDrivers(ASSIGNED)).length(), 1);
    _ = check updateDeliveryStatus("DEL-001", {status: PICKED_UP, occurredAt: "2026-08-17T12:10:00Z"});
    _ = check updateDeliveryStatus("DEL-001", {status: IN_TRANSIT, occurredAt: "2026-08-17T12:15:00Z"});
    _ = check updateDeliveryStatus("DEL-001", {status: DELIVERED, occurredAt: "2026-08-17T12:30:00Z"});
    test:assertEquals((check listDrivers(AVAILABLE)).length(), 1);
}
