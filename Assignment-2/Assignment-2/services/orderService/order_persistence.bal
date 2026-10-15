import ballerinax/mongodb;

public isolated function listOrders(string? customerId = (), string? restaurantId = ())
        returns FoodOrder[]|error {
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("orders");
        map<json> filter = {};
        if customerId is string {
            filter["customerId"] = customerId;
        }
        if restaurantId is string {
            filter["restaurantId"] = restaurantId;
        }
        stream<FoodOrder, error?> orderStream = check collection->find(filter, targetType = FoodOrder);
        return from FoodOrder foodOrder in orderStream
            select foodOrder;
    }
    return memoryListOrders(customerId, restaurantId);
}

public isolated function findOrder(string orderId) returns FoodOrder?|error {
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("orders");
        return collection->findOne({orderId}, targetType = FoodOrder);
    }
    return memoryFindOrder(orderId);
}

public isolated function createOrder(OrderCreateRequest request) returns FoodOrder|error {
    check validateOrderRequest(request);
    if databaseBackend == MONGODB {
        FoodOrder? existing = check findOrder(request.orderId);
        if existing is FoodOrder {
            return error(string `Order '${request.orderId}' already exists`);
        }
        FoodOrder foodOrder = orderFromRequest(request);
        mongodb:Collection collection = check configuredMongoCollection("orders");
        check collection->insertOne(foodOrder);
        return foodOrder;
    }
    return memoryCreateOrder(request);
}

public isolated function transitionOrder(string orderId, OrderTransitionRequest transition)
        returns FoodOrder|error {
    if databaseBackend == MEMORY {
        return memoryTransitionOrder(orderId, transition);
    }
    FoodOrder? currentOrder = check findOrder(orderId);
    if currentOrder is () {
        return error(string `Order '${orderId}' was not found`);
    }
    if !isValidOrderTransition(currentOrder.status, transition.status) {
        return error(string `Order cannot move from ${currentOrder.status} to ${transition.status}`);
    }
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("orders");
        mongodb:UpdateResult result = check collection->updateOne(
            {orderId, status: currentOrder.status},
            {set: {status: transition.status, updatedAt: transition.occurredAt}}
        );
        if result.matchedCount == 0 {
            return error("Order state changed concurrently; reload the order and retry");
        }
    }
    FoodOrder? updatedOrder = check findOrder(orderId);
    return updatedOrder is FoodOrder ? updatedOrder : error(string `Order '${orderId}' was not found`);
}

isolated function validateOrderRequest(OrderCreateRequest request) returns error? {
    if request.items.length() == 0 {
        return error("An order must contain at least one item");
    }
    foreach OrderItem item in request.items {
        if item.quantity <= 0 || item.unitPrice < 0d {
            return error(string `Order item '${item.menuItemId}' has an invalid quantity or price`);
        }
    }
}

isolated function orderFromRequest(OrderCreateRequest request) returns FoodOrder => {
    orderId: request.orderId,
    customerId: request.customerId,
    restaurantId: request.restaurantId,
    deliveryAddressId: request.deliveryAddressId,
    items: request.items.clone(),
    totalAmount: request.totalAmount,
    status: CREATED,
    createdAt: request.createdAt,
    updatedAt: request.createdAt
};

