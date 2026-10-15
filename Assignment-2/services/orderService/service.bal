import ballerina/http;
import ballerina/log;
import ballerina/task;
import ballerina/time;
import ballerina/uuid;
import ballerinax/kafka;

configurable int port = 9090;
configurable decimal timeoutSweepInterval = 30;

type Item record {|
    string menuItemId;
    string name;
    decimal unitPrice;
    int qty;
|};

type Order record {|
    string orderId;
    string customerId;
    string restaurantId;
    Item[] items;
    decimal total;
    string currency = "NAD";
    string deliveryAddress;
    string pickupAddress;
    string paymentMethod;
    string status = "CREATED";
    string paymentStatus = "PENDING";
    string? driverId = ();
    string? cancellationType = ();
    string createdAt;
    string updatedAt;
    string? restaurantAcceptedAt = ();
    string? paymentRequestedAt = ();
    string? deliveryAssignedAt = ();
    string? confirmedDeadline = ();
    string? preparingDeadline = ();
    json[] statusHistory = [];
    int version = 1;
|};

type PlaceOrderRequest record {|
    string customerId;
    string addressId;
    string restaurantId;
    ItemRequest[] items;
    string paymentMethod;
|};

type ItemRequest record {|
    string menuItemId;
    int qty;
|};

function parsePlaceOrderRequest(json raw) returns PlaceOrderRequest|error {
    if !(raw is map<json>) {
        return error("request body must be an object");
    }
    map<json> payload = raw;
    json? customer = payload["customerId"];
    json? address = payload["addressId"];
    json? restaurant = payload["restaurantId"];
    json? payment = payload["paymentMethod"];
    json? rawItems = payload["items"];
    if !(customer is string) || !(address is string) || !(restaurant is string) ||
        !(payment is string) || !(rawItems is json[]) {
        return error("request body has an invalid order shape");
    }
    ItemRequest[] items = [];
    foreach json rawItem in rawItems {
        if !(rawItem is map<json>) {
            return error("request item must be an object");
        }
        map<json> itemPayload = rawItem;
        json? menuItem = itemPayload["menuItemId"];
        json? quantity = itemPayload["qty"];
        if !(menuItem is string) || !(quantity is int) {
            return error("request item has an invalid shape");
        }
        items.push({menuItemId: menuItem, qty: quantity});
    }
    return {
        customerId: customer,
        addressId: address,
        restaurantId: restaurant,
        items: items,
        paymentMethod: payment
    };
}

type ErrorBody record {|
    string 'error;
    string message;
|};

map<Order> orders = {};
map<json[]> eventLog = {};
map<json[]> pendingEvents = {};

service /'order on new http:Listener(port) {
    function init() returns error? {
        check initDurableState();
        check loadDurableOrders();
        if kafkaRuntimeEnabled {
            kafka:Producer|error producer = ensureProducer();
            if producer is error {
                log:printError("order Kafka producer initialization failed", 'error = producer);
                return producer;
            }
            error? warmed = warmupKafkaProducer();
            if warmed is error {
                log:printError("order Kafka producer warm-up failed", 'error = warmed);
                return warmed;
            }
        }
        _ = check task:scheduleJobRecurByFrequency(new DurableRecoveryJob(), 10);
        _ = check task:scheduleJobRecurByFrequency(new OrderTimeoutJob(), timeoutSweepInterval);
        return startKafkaRuntime();
    }

    resource function get health() returns json {
        string status = !kafkaRuntimeEnabled || kafkaConsumerReady ? "UP" : "DOWN";
        return {
            status: status,
            'service: "order",
            kafkaConsumerReady: kafkaConsumerReady
        };
    }

    resource function post orders(http:Request req) returns json|http:Response {
        json|error raw = req.getJsonPayload();
        if raw is error {
            return errorResponse(400, "VALIDATION_ERROR", "request body must be valid JSON");
        }
        PlaceOrderRequest|error bodyResult = parsePlaceOrderRequest(raw);
        if bodyResult is error {
            return errorResponse(400, "VALIDATION_ERROR", "request body has an invalid order shape");
        }
        PlaceOrderRequest body = bodyResult;
        if body.items.length() == 0 || body.customerId.length() == 0 ||
            body.restaurantId.length() == 0 || body.paymentMethod.length() == 0 {
            return errorResponse(400, "VALIDATION_ERROR", "A customer, restaurant, payment method and items are required");
        }
        foreach ItemRequest requested in body.items {
            if requested.qty <= 0 {
                return errorResponse(400, "VALIDATION_ERROR", "item quantity must be greater than zero");
            }
        }
        string id = uuid:createType4AsString();
        Item[] items = [];
        decimal total = 0;
        foreach ItemRequest requested in body.items {
            decimal price = 25.00;
            Item item = {menuItemId: requested.menuItemId, name: "Demo item", unitPrice: price, qty: requested.qty};
            items.push(item);
            total += price * fromInt(requested.qty);
        }
        string now = time:utcToString(time:utcNow());
        Order placed = {
            orderId: id, customerId: body.customerId, restaurantId: body.restaurantId,
            items: items, total: total, deliveryAddress: body.addressId,
            pickupAddress: "Demo Restaurant, Windhoek", paymentMethod: body.paymentMethod,
            createdAt: now, updatedAt: now,
            paymentRequestedAt: now
        };
        orders[id] = placed;
        recordEvent(id, "orders.created", placed);
        json[] createdEvents = eventLog[id] ?: [];
        error? persisted = persistOrderSnapshot(placed, createdEvents);
        if persisted is error {
            return errorResponse(503, "PERSISTENCE_UNAVAILABLE", "order state could not be persisted");
        }
        error? publishResult = publishOrderEvent("orders.created", id, createdEvents[createdEvents.length() - 1]);
        if publishResult is error {
            return errorResponse(503, "EVENT_PUBLISH_FAILED", "order was not published");
        }
        return placed;
    }

    resource function get orders/[string orderId]() returns json|http:Response {
        Order? found = orders[orderId];
        if found is () {
            return errorResponse(404, "NOT_FOUND", "order was not found");
        }
        return found;
    }

    resource function get orders() returns json {
        return orders.toJson();
    }

    resource function post orders/[string orderId]/cancel() returns json|http:Response {
        Order? current = orders[orderId];
        if current is () {
            return errorResponse(404, "NOT_FOUND", "order was not found");
        }
        if !canCancel(current) {
            return errorResponse(409, "INVALID_STATE", "orders can only be cancelled before preparation");
        }
        Order|error cancelled = applyAtomicTransition(current,
            transition(current, "CANCELLED", "CUSTOMER"));
        if cancelled is error {
            if cancelled.message() == "STALE_TRANSITION" {
                return errorResponse(409, "CONFLICT", "order transition is stale");
            }
            log:printError("order cancellation transition failed", 'error = cancelled);
            return errorResponse(500, "INTERNAL_ERROR", "order state could not be transitioned");
        }
        orders[orderId] = cancelled;
        recordEvent(orderId, "orders.cancelled", cancelled, ());
        json[] cancelledEvents = eventLog[orderId] ?: [];
        if cancelledEvents.length() == 0 {
            return errorResponse(500, "INTERNAL_ERROR", "cancellation event was not recorded");
        }
        error? published = publishOrderEvent("orders.cancelled", orderId,
            cancelledEvents[cancelledEvents.length() - 1]);
        if published is error {
            log:printError("order cancellation event publication failed", 'error = published);
            return errorResponse(500, "EVENT_PUBLISH_FAILED", "cancellation event could not be published");
        }
        return cancelled;
    }

    # Internal event adapter used by the Kafka consumer boundary. Production
    # consumers call the same transition function after envelope validation.
    resource function post orders/[string orderId]/events/[string eventType]()
            returns json|http:Response {
        Order? current = orders[orderId];
        if current is () {
            return errorResponse(404, "NOT_FOUND", "order was not found");
        }
        Order|http:Response result = applyEvent(current, eventType);
        if result is http:Response {
            return result;
        }
        if result.version == current.version && result.status == current.status {
            return result;
        }
        Order|error transitioned = applyAtomicTransition(current, result);
        if transitioned is error {
            if transitioned.message() == "STALE_TRANSITION" {
                return errorResponse(409, "CONFLICT", "order transition is stale");
            }
            log:printError("order event transition failed", 'error = transitioned);
            return errorResponse(500, "INTERNAL_ERROR", "order state could not be transitioned");
        }
        orders[orderId] = transitioned;
        recordEvent(orderId, "orders." + transitioned.status.toLowerAscii(), transitioned, ());
        return transitioned;
    }

    # The deployment scheduler invokes this internal endpoint at CFG-8 cadence.
    # Keeping the sweep operation separate makes duplicate scheduler invocations safe.
    resource function post internal/sweep() returns json {
        return {cancelled: sweepExpiredOrders()};
    }
}

class OrderTimeoutJob {
    *task:Job;

    public function execute() {
        _ = sweepExpiredOrders();
    }
}

function sweepExpiredOrders() returns int {
    string now = time:utcToString(time:utcNow());
    int cancelled = 0;
    foreach string id in orders.keys() {
        Order? current = orders[id];
        if current is Order && current.status == "CONFIRMED" &&
            current.confirmedDeadline is string && current.confirmedDeadline < now {
            Order|error timedOut = applyAtomicTransition(current,
                transition(current, "CANCELLED", "TIMEOUT"));
            if timedOut is Order {
                orders[id] = timedOut;
                recordEvent(id, "orders.autocancelled", timedOut, ());
                cancelled += 1;
            }
        } else if current is Order && current.status == "PREPARING" &&
            current.preparingDeadline is string && current.preparingDeadline < now {
            Order|error timedOut = applyAtomicTransition(current,
                transition(current, "CANCELLED", "TIMEOUT"));
            if timedOut is Order {
                orders[id] = timedOut;
                recordEvent(id, "orders.autocancelled", timedOut, ());
                cancelled += 1;
            }
        }
    }
    return cancelled;
}

function fromInt(int value) returns decimal {
    return <decimal>value;
}

function transition(Order current, string status, string? cancellationType = ()) returns Order {
    Order next = current.clone();
    next.status = status;
    next.updatedAt = time:utcToString(time:utcNow());
    next.version = current.version + 1;
    next.cancellationType = cancellationType;
    return next;
}

function canCancel(Order current) returns boolean {
    return current.status == "CREATED" || current.status == "CONFIRMED";
}

function applyEvent(Order current, string eventType) returns Order|http:Response {
    if eventType == "restaurant.accepted" {
        if current.restaurantAcceptedAt is string {
            return current;
        }
        if current.status != "CREATED" {
            return errorResponse(409, "INVALID_STATE", "restaurant acceptance requires CREATED");
        }
        Order accepted = current.clone();
        string acceptedAt = time:utcToString(time:utcNow());
        accepted.restaurantAcceptedAt = acceptedAt;
        accepted.updatedAt = acceptedAt;
        accepted.version = current.version + 1;
        return accepted;
    }
    if eventType == "payments.completed" {
        if current.status == "CONFIRMED" && current.paymentStatus == "PAID" {
            return current;
        }
        if current.status != "CREATED" {
            return errorResponse(409, "INVALID_STATE", "payment completion requires CREATED");
        }
        if current.restaurantAcceptedAt is () {
            return errorResponse(409, "PENDING_EVENT", "payment completion is waiting for restaurant acceptance");
        }
        Order next = transition(current, "CONFIRMED");
        next.paymentStatus = "PAID";
        next.confirmedDeadline = time:utcToString(time:utcAddSeconds(time:utcNow(), 600));
        return next;
    }
    if eventType == "payments.failed" || eventType == "restaurant.rejected" ||
        eventType == "delivery.not_assigned" || eventType == "delivery.failed" {
        if current.status == "DELIVERED" || current.status == "CANCELLED" {
            return errorResponse(409, "INVALID_STATE", "order is terminal");
        }
        Order cancelled = transition(current, "CANCELLED",
            eventType == "payments.failed" ? "PAYMENT_FAILED" :
            eventType == "restaurant.rejected" ? "RESTAURANT_REJECTED" : "TIMEOUT");
        if eventType == "payments.failed" {
            cancelled.paymentStatus = "FAILED";
        }
        return cancelled;
    }
    if eventType == "restaurant.preparing" {
        if current.status != "CONFIRMED" {
            return errorResponse(409, "INVALID_STATE", "preparing requires CONFIRMED");
        }
        Order preparing = transition(current, "PREPARING");
        preparing.preparingDeadline = time:utcToString(time:utcAddSeconds(time:utcNow(), 1800));
        return preparing;
    }
    if eventType == "restaurant.ready" {
        if current.status != "PREPARING" {
            return errorResponse(409, "INVALID_STATE", "ready requires PREPARING");
        }
        return transition(current, "READY");
    }
    if eventType == "delivery.assigned" {
        Order assigned = current.clone();
        assigned.deliveryAssignedAt = time:utcToString(time:utcNow());
        assigned.updatedAt = time:utcToString(time:utcNow());
        assigned.version = current.version + 1;
        return assigned;
    }
    if eventType == "delivery.picked_up" {
        if current.status != "READY" {
            return errorResponse(409, "INVALID_STATE", "pickup requires READY and an assigned driver");
        }
        return transition(current, "OUT_FOR_DELIVERY");
    }
    if eventType == "delivery.completed" {
        if current.status != "OUT_FOR_DELIVERY" {
            return errorResponse(409, "INVALID_STATE", "completion requires OUT_FOR_DELIVERY");
        }
        return transition(current, "DELIVERED");
    }
    return errorResponse(400, "INVALID_EVENT", "unsupported order event");
}

function recordEvent(string orderId, string eventType, Order placed, string? sourceEventId = ()) {
    string eventId = uuid:createType4AsString();
    string deterministicSource = sourceEventId is string ? sourceEventId :
        orderId + ":" + eventType + ":" + placed.version.toString();
    string|error deterministic = derivedEventId(deterministicSource, eventType);
    if deterministic is string {
        eventId = deterministic;
    }
    json event = {
        eventId: eventId, eventType: eventType, orderId: orderId,
        occurredAt: time:utcToString(time:utcNow()), correlationId: orderId,
        producerService: "order-service",
        data: {orderSummary: {customerId: placed.customerId, restaurantId: placed.restaurantId,
            total: placed.total, currency: placed.currency, deliveryAddress: placed.deliveryAddress,
            driverId: placed.driverId}, payload: placed, previousStatus: placed.status}
    };
    json[] events = eventLog[orderId] ?: [];
    events.push(event);
    eventLog[orderId] = events;
}

function errorResponse(int status, string code, string message) returns http:Response {
    http:Response response = new;
    response.statusCode = status;
    response.setJsonPayload(<ErrorBody>{'error: code, message: message});
    return response;
}
