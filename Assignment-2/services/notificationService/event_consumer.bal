// Kafka consumer for order lifecycle events.
//
// A task job polls Kafka once a second. Every record is committed once it has
// been handled, including records that cannot be decoded and events already
// seen. This service only consumes; it publishes nothing.

import ballerina/lang.'string as str;
import ballerina/log;
import ballerina/task;
import ballerinax/kafka;

// Kafka stays off unless the Docker runtime enables it, so unit tests need no broker.
configurable boolean kafkaRuntimeEnabled = false;
configurable string kafkaBootstrap = "kafka:9092";

const string ORDER_CREATED = "orders.created";

final kafka:ConsumerConfiguration notificationConsumerConfiguration = {
    groupId: "notification-service",
    topics: [
        "orders.created",
        "orders.confirmed",
        "orders.preparing",
        "orders.ready",
        "orders.out_for_delivery",
        "orders.delivered",
        "orders.cancelled",
        "orders.autocancelled"
    ],
    offsetReset: "earliest",
    autoCommit: false,
    pollingInterval: 1,
    maxPollRecords: 10
};

// The fields of the shared event envelope this service reads.
// `data.orderSummary` carries `customerId` and `restaurantId`.
type NotificationEvent record {|
    string eventId;
    string eventType;
    string orderId;
    string correlationId;
    json occurredAt = ();
    string producerService = "";
    json data = {};
|};

kafka:Consumer|error? notificationConsumer = ();

// Event ids already turned into notifications (in memory; cleared on restart).
map<boolean> notificationProcessedEvents = {};

// Creates the consumer and schedules the polling job when Kafka is enabled.
function startNotificationKafkaRuntime() returns error? {
    if !kafkaRuntimeEnabled {
        return;
    }
    kafka:Consumer|error consumer = new (kafkaBootstrap, notificationConsumerConfiguration);
    if consumer is error {
        return consumer;
    }
    notificationConsumer = consumer;
    _ = check task:scheduleJobRecurByFrequency(new NotificationKafkaJob(), 1);
}

// Polls one batch of records and handles each one.
class NotificationKafkaJob {
    *task:Job;

    public function execute() {
        kafka:Consumer|error? current = notificationConsumer;
        if current !is kafka:Consumer {
            return;
        }
        kafka:AnydataConsumerRecord[]|kafka:Error records = current->poll(1);
        if records is kafka:Error {
            log:printError("notification Kafka poll failed", 'error = records);
            return;
        }
        foreach kafka:AnydataConsumerRecord kafkaRecord in records {
            handleNotificationRecord(current, kafkaRecord);
        }
    }
}

// Turns one Kafka record into notifications, then commits it.
// Undecodable records and repeated event ids are committed without notifying.
function handleNotificationRecord(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord) {
    NotificationEvent? event = decodeEvent(kafkaRecord);
    if event is () || isProcessed(event.eventId) {
        commitNotificationRecord(consumer, kafkaRecord);
        return;
    }
    notifyRecipients(event);
    notificationProcessedEvents[event.eventId] = true;
    commitNotificationRecord(consumer, kafkaRecord);
}

// Creates the notifications for one event:
// the customer on every event, and the restaurant on `orders.created` only.
function notifyRecipients(NotificationEvent event) {
    string customerId = orderSummaryField(event.data, "customerId");
    string restaurantId = orderSummaryField(event.data, "restaurantId");

    if customerId.length() > 0 {
        _ = addNotification(RECIPIENT_CUSTOMER, customerId, event.orderId, event.eventId,
                "Order status changed to " + event.eventType);
    }
    if restaurantId.length() > 0 && event.eventType == ORDER_CREATED {
        _ = addNotification(RECIPIENT_RESTAURANT, restaurantId, event.orderId, event.eventId,
                "New order received");
    }
}

// Decodes a record value (UTF-8 JSON) into an event envelope.
// Returns `()` when the value is not bytes, not UTF-8, not JSON, or not an envelope.
function decodeEvent(kafka:AnydataConsumerRecord kafkaRecord) returns NotificationEvent? {
    anydata value = kafkaRecord.value;
    if value !is byte[] {
        return ();
    }
    string|error raw = str:fromBytes(value);
    if raw is error {
        return ();
    }
    json|error parsed = raw.fromJsonString();
    if parsed is error {
        return ();
    }
    NotificationEvent|error event = parsed.cloneWithType(NotificationEvent);
    if event is error {
        return ();
    }
    return event;
}

// Reads a string field from `data.orderSummary`; returns "" when it is missing.
function orderSummaryField(json data, string fieldName) returns string {
    json|error summary = data.orderSummary;
    if summary is map<json> {
        json? value = summary[fieldName];
        if value is string {
            return value;
        }
    }
    return "";
}

function isProcessed(string eventId) returns boolean {
    return notificationProcessedEvents[eventId] == true;
}

// Commits the offset after this record so it is not delivered again.
function commitNotificationRecord(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord) {
    kafka:PartitionOffset committed = {
        partition: kafkaRecord.offset.partition,
        offset: kafkaRecord.offset.offset + 1
    };
    kafka:Error? result = consumer->commitOffset([committed]);
    if result is kafka:Error {
        log:printError("notification Kafka offset commit failed", 'error = result);
    }
}
