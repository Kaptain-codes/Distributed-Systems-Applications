import ballerina/http;

configurable int servicePort = 9103;

isolated function orderNotFound(string message) returns NotFoundResponse => {body: {message}};

isolated function orderConflict(string message) returns ConflictResponse => {body: {message}};

isolated function invalidOrder(string message) returns BadRequestResponse => {body: {message}};

// Owns the central food-order aggregate and its lifecycle state machine.
service /orders on new http:Listener(servicePort) {
    // Provides a lightweight readiness signal for container orchestration.
    isolated resource function get health() returns map<string> =>
        {status: "UP", component: "order_service"};

    // Lists orders with optional customer and restaurant filters.
    isolated resource function get .(string? customerId, string? restaurantId)
            returns FoodOrder[]|error => listOrders(customerId, restaurantId);

    // Places a new order in the CREATED state.
    isolated resource function post .(OrderCreateRequest request)
            returns FoodOrder|ConflictResponse|BadRequestResponse|error {
        FoodOrder|error result = createOrder(request);
        if result is FoodOrder {
            check publishOrderCreatedEvent(result);
            return result;
        }
        return result.message().includes("already exists") ? orderConflict(result.message()) :
            invalidOrder(result.message());
    }

    // Returns a single order.
    isolated resource function get [string orderId]() returns FoodOrder|NotFoundResponse|error {
        FoodOrder? foodOrder = check findOrder(orderId);
        return foodOrder is FoodOrder ? foodOrder :
            orderNotFound(string `Order '${orderId}' was not found`);
    }

    // Moves an order through a validated lifecycle transition.
    isolated resource function post [string orderId]/transitions(OrderTransitionRequest transition)
            returns FoodOrder|NotFoundResponse|ConflictResponse|error {
        FoodOrder|error result = transitionOrder(orderId, transition);
        if result is FoodOrder {
            check publishOrderStatusEvent(result);
            return result;
        }
        return result.message().includes("not found") ? orderNotFound(result.message()) :
            orderConflict(result.message());
    }
}

