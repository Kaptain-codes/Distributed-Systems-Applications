import ballerinax/mongodb;

public isolated function listDrivers(DriverStatus? status = ()) returns Driver[]|error {
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("drivers");
        map<json> filter = status is DriverStatus ? {status} : {};
        stream<Driver, error?> driverStream = check collection->find(filter, targetType = Driver);
        return from Driver driver in driverStream
            select driver;
    }
    return memoryListDrivers(status);
}

public isolated function registerDriver(Driver driver) returns Driver|error {
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("drivers");
        Driver? existing = check collection->findOne({driverId: driver.driverId}, targetType = Driver);
        if existing is Driver {
            return error(string `Driver '${driver.driverId}' already exists`);
        }
        check collection->insertOne(driver);
        return driver;
    }
    return memoryRegisterDriver(driver);
}

public isolated function listDeliveries(string? driverId = ()) returns Delivery[]|error {
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("deliveries");
        map<json> filter = driverId is string ? {driverId} : {};
        stream<Delivery, error?> deliveryStream =
            check collection->find(filter, targetType = Delivery);
        return from Delivery delivery in deliveryStream
            select delivery;
    }
    return memoryListDeliveries(driverId);
}

public isolated function findDelivery(string deliveryId) returns Delivery?|error {
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("deliveries");
        return collection->findOne({deliveryId}, targetType = Delivery);
    }
    return memoryFindDelivery(deliveryId);
}

public isolated function assignDelivery(DeliveryAssignmentRequest request)
        returns Delivery|error {
    Delivery delivery = deliveryFromRequest(request);
    if databaseBackend == MONGODB {
        mongodb:Collection drivers = check configuredMongoCollection("drivers");
        mongodb:UpdateResult reservation = check drivers->updateOne(
            {driverId: request.driverId, status: AVAILABLE}, {set: {status: ASSIGNED}});
        if reservation.matchedCount == 0 {
            return driverAssignmentFailure(request.driverId);
        }
        mongodb:Collection deliveries = check configuredMongoCollection("deliveries");
        error? insertionError = deliveries->insertOne(delivery);
        if insertionError is error {
            mongodb:UpdateResult|error rollbackResult = drivers->updateOne(
                {driverId: request.driverId}, {set: {status: AVAILABLE}});
            if rollbackResult is error {
                return error("Delivery insertion and driver reservation rollback both failed",
                    insertionError, driverId = request.driverId);
            }
            return insertionError;
        }
        return delivery;
    }
    return memoryAssignDelivery(request);
}

public isolated function updateDeliveryStatus(string deliveryId, DeliveryStatusUpdate update)
        returns Delivery|error {
    if databaseBackend == MEMORY {
        return memoryUpdateDeliveryStatus(deliveryId, update);
    }
    Delivery? currentDelivery = check findDelivery(deliveryId);
    if currentDelivery is () {
        return error(string `Delivery '${deliveryId}' was not found`);
    }
    if !validDeliveryTransition(currentDelivery.status, update.status) {
        return error(string `Delivery cannot move from ${currentDelivery.status} to ${update.status}`);
    }
    boolean terminal = update.status == DELIVERED || update.status == CANCELLED;
    if databaseBackend == MONGODB {
        mongodb:Collection deliveries = check configuredMongoCollection("deliveries");
        mongodb:UpdateResult statusUpdate = check deliveries->updateOne(
            {deliveryId, status: currentDelivery.status},
            {set: {status: update.status, updatedAt: update.occurredAt}});
        if statusUpdate.matchedCount == 0 {
            return error("Delivery state changed concurrently; reload and retry");
        }
        if terminal {
            mongodb:Collection drivers = check configuredMongoCollection("drivers");
            _ = check drivers->updateOne({driverId: currentDelivery.driverId},
                {set: {status: AVAILABLE}});
        }
    }
    Delivery? updatedDelivery = check findDelivery(deliveryId);
    return updatedDelivery is Delivery ? updatedDelivery :
        error(string `Delivery '${deliveryId}' was not found`);
}

isolated function deliveryFromRequest(DeliveryAssignmentRequest request) returns Delivery => {
    deliveryId: request.deliveryId,
    orderId: request.orderId,
    driverId: request.driverId,
    restaurantAddress: request.restaurantAddress,
    customerAddress: request.customerAddress,
    status: ASSIGNED,
    assignedAt: request.assignedAt,
    updatedAt: request.assignedAt
};

isolated function validDeliveryTransition(DeliveryStatus currentStatus,
        DeliveryStatus requestedStatus) returns boolean =>
    (currentStatus == ASSIGNED && (requestedStatus == PICKED_UP || requestedStatus == CANCELLED)) ||
    (currentStatus == PICKED_UP && requestedStatus == IN_TRANSIT) ||
    (currentStatus == IN_TRANSIT && requestedStatus == DELIVERED);

isolated function driverAssignmentFailure(string driverId) returns Delivery|error {
    Driver[] matchingDrivers = check listDrivers();
    foreach Driver driver in matchingDrivers {
        if driver.driverId == driverId {
            return error(string `Driver '${driverId}' is not available`);
        }
    }
    return error(string `Driver '${driverId}' was not found`);
}
