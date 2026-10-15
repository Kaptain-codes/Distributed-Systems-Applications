import ballerina/time;

public type OrderSummary record {|
    string customerId;
    string restaurantId;
    decimal total;
    string currency = "NAD";
    string deliveryAddress;
    string? driverId = ();
|};

public type EventData record {|
    OrderSummary orderSummary;
    json payload = {};
|};

public type EventEnvelope record {|
    string eventId;
    string eventType;
    time:Utc occurredAt;
    string orderId;
    string correlationId;
    string producerService;
    EventData data;
|};

public function serializeEnvelope(EventEnvelope event) returns string {
    return event.toJsonString();
}

public function deserializeEnvelope(string raw) returns EventEnvelope|error {
    json parsed = check raw.fromJsonString();
    return <EventEnvelope>parsed;
}

public type ErrorResponse record {|
    string 'error;
    string message;
|};

public const string[] BASE_TOPICS = [
    "orders.created", "orders.confirmed", "orders.preparing", "orders.ready",
    "orders.out_for_delivery", "orders.delivered", "orders.cancelled",
    "orders.autocancelled", "payments.completed", "payment.requested",
    "payments.failed", "payments.cancelled", "payments.refunded",
    "restaurant.accepted", "restaurant.rejected", "restaurant.preparing",
    "restaurant.ready", "delivery.assigned", "delivery.picked_up",
    "delivery.not_assigned", "delivery.completed", "delivery.cancelled",
    "delivery.failed"
];

public function isBaseTopic(string topic) returns boolean {
    foreach string candidate in BASE_TOPICS {
        if candidate == topic {
            return true;
        }
    }
    return false;
}

public function dlqTopic(string topic) returns string {
    return topic + ".dlq";
}

public function validateEnvelope(EventEnvelope event) returns ErrorResponse? {
    if !isBaseTopic(event.eventType) {
        return {'error: "INVALID_EVENT", message: "eventType is not a registered base topic"};
    }
    if event.orderId.length() == 0 || event.eventId.length() == 0 ||
        event.correlationId.length() == 0 {
        return {'error: "INVALID_EVENT", message: "eventId, orderId and correlationId are required"};
    }
    if event.data.orderSummary.currency != "NAD" {
        return {'error: "INVALID_EVENT", message: "currency must be NAD"};
    }
    return ();
}

public function errorResponse(string code, string message) returns ErrorResponse {
    return {'error: code, message: message};
}
