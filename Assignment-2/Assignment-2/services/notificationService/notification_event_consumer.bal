import ballerina/log;
import ballerinax/kafka;

configurable boolean kafkaEnabled = false;
configurable string kafkaBootstrapServers = kafka:DEFAULT_URL;

type DomainEvent record {|
    readonly string eventId;
    string eventType;
    string aggregateId;
    string 'source;
    int schemaVersion;
    string occurredAt;
    json payload;
|};

type NotificationEventPayload record {
    string customerId?;
    string restaurantId?;
    string driverId?;
};

final kafka:Listener? notificationEventListener = kafkaEnabled ? checkpanic new (kafkaBootstrapServers, {
        groupId: "notification-service-lifecycle",
        clientId: "notification-service-consumer",
        topics: [
            "orders.created",
            "orders.confirmed",
            "orders.preparing",
            "orders.ready",
            "orders.out_for_delivery",
            "orders.delivered",
            "orders.cancelled",
            "payments.completed",
            "payments.failed",
            "delivery.assigned"
        ],
        offsetReset: kafka:OFFSET_RESET_EARLIEST,
        autoCommit: false,
        pollingInterval: 1
    }) : ();

kafka:Service lifecycleNotificationConsumer = service object {
    // Converts domain events into idempotent notification records.
    remote isolated function onConsumerRecord(kafka:Caller caller, DomainEvent[] events) {
        foreach DomainEvent domainEvent in events {
            error? result = createLifecycleNotification(domainEvent);
            if result is error {
                log:printError("Lifecycle notification creation failed",
                        eventId = domainEvent.eventId, eventType = domainEvent.eventType, 'error = result);
                return;
            }
        }
        kafka:Error? commitResult = caller->'commit();
        if commitResult is kafka:Error {
            log:printError("Notification consumer offset commit failed", 'error = commitResult);
        }
    }
};

function init() returns error? {
    kafka:Listener? eventListener = notificationEventListener;
    if eventListener is kafka:Listener {
        check eventListener.attach(lifecycleNotificationConsumer);
        check eventListener.'start();
    }
}

function stop() returns error? {
    kafka:Listener? eventListener = notificationEventListener;
    if eventListener is kafka:Listener {
        check eventListener.gracefulStop();
    }
}

isolated function createLifecycleNotification(DomainEvent domainEvent) returns error? {
    NotificationEventPayload eventPayload = check domainEvent.payload.cloneWithType();
    [RecipientType, string]? recipient = notificationRecipient(domainEvent.eventType, eventPayload);
    if recipient is () {
        log:printWarn("Lifecycle event has no resolvable notification recipient",
                eventId = domainEvent.eventId, eventType = domainEvent.eventType);
        return;
    }

    NotificationRequest request = {
        notificationId: string `event-${domainEvent.eventId}`,
        recipientType: recipient[0],
        recipientId: recipient[1],
        channel: PUSH,
        subject: notificationSubject(domainEvent.eventType),
        message: string `Order ${domainEvent.aggregateId}: ${notificationMessage(domainEvent.eventType)}`,
        createdAt: domainEvent.occurredAt
    };
    Notification|error result = queueNotification(request);
    if result is error && !result.message().includes("already exists") {
        return result;
    }
}

isolated function notificationRecipient(string eventType,
        NotificationEventPayload eventPayload) returns [RecipientType, string]? {
    string? restaurantId = eventPayload.restaurantId;
    if eventType == "orders.created" && restaurantId is string {
        [RecipientType, string] recipient = [RESTAURANT, restaurantId];
        return recipient;
    }
    string? driverId = eventPayload.driverId;
    if eventType == "delivery.assigned" && driverId is string {
        [RecipientType, string] recipient = [DRIVER, driverId];
        return recipient;
    }
    string? customerId = eventPayload.customerId;
    if customerId is string {
        [RecipientType, string] recipient = [CUSTOMER, customerId];
        return recipient;
    }
    return ();
}

isolated function notificationSubject(string eventType) returns string {
    match eventType {
        "orders.created" => {
            return "New order received";
        }
        "payments.completed" => {
            return "Payment completed";
        }
        "payments.failed" => {
            return "Payment failed";
        }
        "delivery.assigned" => {
            return "Delivery assigned";
        }
        _ => {
            return "Order status updated";
        }
    }
}

isolated function notificationMessage(string eventType) returns string {
    match eventType {
        "orders.created" => {
            return "the order is awaiting payment processing.";
        }
        "orders.confirmed" => {
            return "the restaurant confirmed the order.";
        }
        "orders.preparing" => {
            return "the kitchen is preparing the order.";
        }
        "orders.ready" => {
            return "the order is ready for collection.";
        }
        "orders.out_for_delivery" => {
            return "the order is out for delivery.";
        }
        "orders.delivered" => {
            return "the order was delivered.";
        }
        "orders.cancelled" => {
            return "the order was cancelled.";
        }
        "payments.completed" => {
            return "payment was approved.";
        }
        "payments.failed" => {
            return "payment could not be completed.";
        }
        "delivery.assigned" => {
            return "a delivery has been assigned to you.";
        }
        _ => {
            return "the order lifecycle changed.";
        }
    }
}
