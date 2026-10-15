isolated table<FoodOrder> key(orderId) orderTable = table [];

// Checks whether a requested transition follows the order lifecycle.
public isolated function isValidOrderTransition(OrderStatus currentStatus,
        OrderStatus requestedStatus) returns boolean {
    if requestedStatus == CANCELLED {
        return currentStatus == CREATED || currentStatus == CONFIRMED || currentStatus == PREPARING;
    }
    if currentStatus == CREATED {
        return requestedStatus == CONFIRMED;
    }
    if currentStatus == CONFIRMED {
        return requestedStatus == PREPARING;
    }
    if currentStatus == PREPARING {
        return requestedStatus == READY;
    }
    if currentStatus == READY {
        return requestedStatus == OUT_FOR_DELIVERY;
    }
    if currentStatus == OUT_FOR_DELIVERY {
        return requestedStatus == DELIVERED;
    }
    return false;
}

// Returns order snapshots, optionally filtered by customer or restaurant.
isolated function memoryListOrders(string? customerId = (), string? restaurantId = ())
        returns FoodOrder[] {
    lock {
        FoodOrder[] matchingOrders = from FoodOrder foodOrder in orderTable
            where customerId is () || foodOrder.customerId == customerId
            where restaurantId is () || foodOrder.restaurantId == restaurantId
            select foodOrder.clone();
        return matchingOrders.clone();
    }
}

// Finds an order without exposing mutable state.
isolated function memoryFindOrder(string orderId) returns FoodOrder? {
    lock {
        FoodOrder? foodOrder = orderTable[orderId];
        return foodOrder is FoodOrder ? foodOrder.clone() : ();
    }
}

// Creates an order in the only legal initial state: CREATED.
isolated function memoryCreateOrder(OrderCreateRequest request) returns FoodOrder|error {
    lock {
        OrderCreateRequest storedRequest = request.clone();
        if orderTable.hasKey(storedRequest.orderId) {
            return error(string `Order '${storedRequest.orderId}' already exists`);
        }
        if storedRequest.items.length() == 0 {
            return error("An order must contain at least one item");
        }
        foreach OrderItem item in storedRequest.items {
            if item.quantity <= 0 || item.unitPrice < 0d {
                return error(string `Order item '${item.menuItemId}' has an invalid quantity or price`);
            }
        }
        FoodOrder foodOrder = {
            orderId: storedRequest.orderId,
            customerId: storedRequest.customerId,
            restaurantId: storedRequest.restaurantId,
            deliveryAddressId: storedRequest.deliveryAddressId,
            items: storedRequest.items,
            totalAmount: storedRequest.totalAmount,
            status: CREATED,
            createdAt: storedRequest.createdAt,
            updatedAt: storedRequest.createdAt
        };
        orderTable.add(foodOrder);
        return foodOrder.clone();
    }
}

// Applies a lifecycle transition atomically to prevent concurrent state races.
isolated function memoryTransitionOrder(string orderId, OrderTransitionRequest transition)
        returns FoodOrder|error {
    lock {
        FoodOrder? foodOrder = orderTable[orderId];
        if foodOrder is () {
            return error(string `Order '${orderId}' was not found`);
        }
        if !isValidOrderTransition(foodOrder.status, transition.status) {
            return error(string `Order cannot move from ${foodOrder.status} to ${transition.status}`);
        }
        foodOrder.status = transition.status;
        foodOrder.updatedAt = transition.occurredAt;
        return foodOrder.clone();
    }
}

// Clears repository state for deterministic tests.
public isolated function clearOrders() {
    lock {
        orderTable = table [];
    }
}

