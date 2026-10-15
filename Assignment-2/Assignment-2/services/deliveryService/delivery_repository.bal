type DeliveryStore record {|
    table<Driver> key(driverId) drivers;
    table<Delivery> key(deliveryId) deliveries;
|};

// Drivers and assignments share one isolated root because assignment must
// update both records atomically.
isolated DeliveryStore deliveryStore = {drivers: table [], deliveries: table []};

isolated function memoryListDrivers(DriverStatus? status = ()) returns Driver[] {
    lock {
        Driver[] matchingDrivers = from Driver driver in deliveryStore.drivers
            where status is () || driver.status == status
            select driver.clone();
        return matchingDrivers.clone();
    }
}

isolated function memoryRegisterDriver(Driver driver) returns Driver|error {
    lock {
        Driver storedDriver = driver.clone();
        if deliveryStore.drivers.hasKey(storedDriver.driverId) {
            return error(string `Driver '${storedDriver.driverId}' already exists`);
        }
        deliveryStore.drivers.add(storedDriver);
        return storedDriver.clone();
    }
}

isolated function memoryListDeliveries(string? driverId = ()) returns Delivery[] {
    lock {
        Delivery[] matchingDeliveries = from Delivery delivery in deliveryStore.deliveries
            where driverId is () || delivery.driverId == driverId
            select delivery.clone();
        return matchingDeliveries.clone();
    }
}

isolated function memoryFindDelivery(string deliveryId) returns Delivery? {
    lock {
        Delivery? delivery = deliveryStore.deliveries[deliveryId];
        return delivery is Delivery ? delivery.clone() : ();
    }
}

// Assigns only an available driver and reserves that driver atomically.
isolated function memoryAssignDelivery(DeliveryAssignmentRequest request)
        returns Delivery|error {
    lock {
        DeliveryAssignmentRequest storedRequest = request.clone();
        if deliveryStore.deliveries.hasKey(storedRequest.deliveryId) {
            return error(string `Delivery '${storedRequest.deliveryId}' already exists`);
        }
        Driver? driver = deliveryStore.drivers[storedRequest.driverId];
        if driver is () {
            return error(string `Driver '${storedRequest.driverId}' was not found`);
        }
        if driver.status != AVAILABLE {
            return error(string `Driver '${storedRequest.driverId}' is not available`);
        }
        Delivery delivery = {
            deliveryId: storedRequest.deliveryId,
            orderId: storedRequest.orderId,
            driverId: storedRequest.driverId,
            restaurantAddress: storedRequest.restaurantAddress,
            customerAddress: storedRequest.customerAddress,
            status: ASSIGNED,
            assignedAt: storedRequest.assignedAt,
            updatedAt: storedRequest.assignedAt
        };
        driver.status = ASSIGNED;
        deliveryStore.deliveries.add(delivery);
        return delivery.clone();
    }
}

// Advances delivery state and releases the driver on a terminal state.
isolated function memoryUpdateDeliveryStatus(string deliveryId, DeliveryStatusUpdate update)
        returns Delivery|error {
    lock {
        DeliveryStatusUpdate storedUpdate = update.clone();
        Delivery? delivery = deliveryStore.deliveries[deliveryId];
        if delivery is () {
            return error(string `Delivery '${deliveryId}' was not found`);
        }
        boolean validTransition =
            (delivery.status == ASSIGNED &&
                (storedUpdate.status == PICKED_UP || storedUpdate.status == CANCELLED)) ||
            (delivery.status == PICKED_UP && storedUpdate.status == IN_TRANSIT) ||
            (delivery.status == IN_TRANSIT && storedUpdate.status == DELIVERED);
        if !validTransition {
            return error(string `Delivery cannot move from ${delivery.status} to ${storedUpdate.status}`);
        }
        delivery.status = storedUpdate.status;
        delivery.updatedAt = storedUpdate.occurredAt;
        if storedUpdate.status == DELIVERED || storedUpdate.status == CANCELLED {
            Driver? driver = deliveryStore.drivers[delivery.driverId];
            if driver is Driver {
                driver.status = AVAILABLE;
            }
        }
        return delivery.clone();
    }
}

public isolated function clearDeliveryStore() {
    lock {
        deliveryStore = {drivers: table [], deliveries: table []};
    }
}

