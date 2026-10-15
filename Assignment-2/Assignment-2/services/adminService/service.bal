import ballerina/http;

configurable int servicePort = 9107;

isolated function invalidReport(string message) returns BadRequestResponse => {body: {message}};

// Serves reporting read models without owning operational service data.
service /admin/reports on new http:Listener(servicePort) {
    // Provides a lightweight readiness signal for container orchestration.
    isolated resource function get health() returns map<string> =>
        {status: "UP", component: "admin_service"};

    isolated resource function get restaurant_statistics() returns RestaurantStatistics[]|error =>
        getRestaurantStatistics();

    isolated resource function put restaurant_statistics/[string restaurantId](
            RestaurantStatistics statistics) returns RestaurantStatistics|BadRequestResponse {
        if restaurantId != statistics.restaurantId {
            return invalidReport("Restaurant identifier in the path and body must match");
        }
        RestaurantStatistics|error result = saveRestaurantStatistics(statistics);
        return result is error ? invalidReport(result.message()) : result;
    }

    isolated resource function get delivery_performance() returns DeliveryPerformance[]|error =>
        getDeliveryPerformance();

    isolated resource function put delivery_performance/[string driverId](
            DeliveryPerformance performance) returns DeliveryPerformance|BadRequestResponse {
        if driverId != performance.driverId {
            return invalidReport("Driver identifier in the path and body must match");
        }
        DeliveryPerformance|error result = saveDeliveryPerformance(performance);
        return result is error ? invalidReport(result.message()) : result;
    }

    isolated resource function get summary() returns PlatformSummary|error => getPlatformSummary();
}
