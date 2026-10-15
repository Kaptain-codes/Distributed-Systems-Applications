import ballerina/test;

@test:BeforeEach
function resetReportRepository() {
    clearReports();
}

@test:Config
function testPlatformSummaryAggregation() returns error? {
    _ = check saveRestaurantStatistics({
                                           restaurantId: "RES-001",
                                           restaurantName: "Windhoek Kitchen",
                                           totalOrders: 12,
                                           completedOrders: 10,
                                           cancelledOrders: 2,
                                           grossRevenue: 2500.00
                                       });
    _ = check saveDeliveryPerformance({
                                          driverId: "DRV-001",
                                          driverName: "Paulus Amutenya",
                                          assignedDeliveries: 10,
                                          completedDeliveries: 9,
                                          averageDeliveryMinutes: 28.5
                                      });
    PlatformSummary summary = check getPlatformSummary();
    test:assertEquals(summary.totalOrders, 12);
    test:assertEquals(summary.completedDeliveries, 9);
    test:assertEquals(summary.grossRevenue, 2500d);
}
