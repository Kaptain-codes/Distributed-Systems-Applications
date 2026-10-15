import ballerina/http;

configurable int servicePort = 9105;

isolated function deliveryNotFound(string message) returns NotFoundResponse => {body: {message}};

isolated function deliveryConflict(string message) returns ConflictResponse => {body: {message}};

// Coordinates driver availability, assignment, and delivery progress.
service /delivery on new http:Listener(servicePort) {
    // Provides a lightweight readiness signal for container orchestration.
    isolated resource function get health() returns map<string> =>
        {status: "UP", component: "delivery_service"};

    isolated resource function get drivers(DriverStatus? status) returns Driver[]|error => listDrivers(status);

    isolated resource function post drivers(Driver driver) returns Driver|ConflictResponse {
        Driver|error result = registerDriver(driver);
        return result is error ? deliveryConflict(result.message()) : result;
    }

    isolated resource function get assignments(string? driverId) returns Delivery[]|error =>
        listDeliveries(driverId);

    isolated resource function post assignments(DeliveryAssignmentRequest request)
            returns Delivery|NotFoundResponse|ConflictResponse|error {
        Delivery|error result = assignDelivery(request);
        if result is Delivery {
            check publishDeliveryAssignedEvent(result);
            return result;
        }
        return result.message().includes("not found") ? deliveryNotFound(result.message()) :
            deliveryConflict(result.message());
    }

    isolated resource function get assignments/[string deliveryId]()
            returns Delivery|NotFoundResponse|error {
        Delivery? delivery = check findDelivery(deliveryId);
        return delivery is Delivery ? delivery :
            deliveryNotFound(string `Delivery '${deliveryId}' was not found`);
    }

    isolated resource function post assignments/[string deliveryId]/status(DeliveryStatusUpdate update)
            returns Delivery|NotFoundResponse|ConflictResponse|error {
        Delivery|error result = updateDeliveryStatus(deliveryId, update);
        if result is Delivery {
            check publishDeliveryCompletedEvent(result);
            return result;
        }
        return result.message().includes("not found") ? deliveryNotFound(result.message()) :
            deliveryConflict(result.message());
    }
}

