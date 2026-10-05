import ballerinax/kafka;
import ballerina/http;
import ballerina/log;
import ballerina/lang.'string as str;
import ballerina/os;
import ballerina/lang.runtime as runtime;
import ballerina/task;
import ballerina/time;

configurable boolean kafkaRuntimeEnabled = false;
configurable int consumerRetries = 3;
configurable decimal consumerRetryBackoffFirst = 1;
configurable decimal consumerRetryBackoffSecond = 5;
configurable decimal consumerPollTimeout = 1;
// Test-only crash point. Production and normal Docker runs leave this empty.
configurable string testFailurePoint = "";
configurable string testFailureEventId = "";

type RuntimeEventData record {|
    json orderSummary = {};
    json payload = {};
    json previousStatus = {};
|};

type RuntimeEventEnvelope record {|
    string eventId;
    string eventType;
    string occurredAt;
    string orderId;
    string correlationId;
    string producerService;
    RuntimeEventData data;
|};

final string[] orderConsumerTopics = [
    "restaurant.accepted", "restaurant.rejected", "restaurant.preparing",
    "restaurant.ready", "payments.completed", "payments.failed",
    "delivery.assigned", "delivery.picked_up", "delivery.completed",
    "delivery.not_assigned", "delivery.failed"
];

final kafka:ConsumerConfiguration orderConsumerConfiguration = {
    groupId: "order-service",
    topics: orderConsumerTopics,
    offsetReset: "earliest",
    autoCommit: false,
    pollingInterval: 1,
    maxPollRecords: 10
};

kafka:Consumer|error? orderConsumer = ();
map<boolean> processedRuntimeEvents = {};

function startKafkaRuntime() returns error? {
    if !kafkaRuntimeEnabled {
        return;
    }
    kafka:Consumer|error consumer = new (kafkaBootstrap, orderConsumerConfiguration);
    if consumer is error {
        return consumer;
    }
    orderConsumer = consumer;
    _ = check task:scheduleJobRecurByFrequency(new OrderKafkaConsumerJob(), 1);
}

class OrderKafkaConsumerJob {
    *task:Job;

    public function execute() {
        kafka:Consumer|error? consumerValue = orderConsumer;
        if consumerValue is kafka:Consumer {
            kafka:AnydataConsumerRecord[]|kafka:Error records = consumerValue->poll(consumerPollTimeout);
            if records is kafka:Error {
                log:printError("order Kafka poll failed", 'error = records);
                runtime:sleep(1);
                return;
            }
            foreach kafka:AnydataConsumerRecord kafkaRecord in records {
                handleRuntimeRecord(consumerValue, kafkaRecord);
            }
        }
    }
}

function handleRuntimeRecord(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord) {
    string raw;
    if kafkaRecord.value is byte[] {
        byte[] bytes = <byte[]>kafkaRecord.value;
        string|error decoded = str:fromBytes(bytes);
        if decoded is error {
            checkParkAndCommit(consumer, kafkaRecord, "record value is not UTF-8", 1);
            return;
        }
        raw = decoded;
    } else {
        checkParkAndCommit(consumer, kafkaRecord, "record value is not a byte array", 1);
        return;
    }

    json|error parsed = raw.fromJsonString();
    if parsed is error {
        checkParkAndCommit(consumer, kafkaRecord, "invalid event envelope: " + parsed.message(), 1);
        return;
    }
    RuntimeEventEnvelope|error event = parsed.cloneWithType(RuntimeEventEnvelope);
    if event is error {
        checkParkAndCommit(consumer, kafkaRecord, "invalid event envelope: " + event.message(), 1);
        return;
    }
    if event.eventId.length() == 0 || event.orderId.length() == 0 ||
        event.correlationId.length() == 0 || !isRuntimeTopic(event.eventType) {
        checkParkAndCommit(consumer, kafkaRecord, "event envelope validation failed", 1);
        return;
    }
    boolean|error claimed = claimDurableEvent(event.eventId, event.orderId, raw,
        kafkaRecord.offset.partition.topic, kafkaRecord.offset.partition.partition,
        kafkaRecord.offset.offset);
    if claimed is error {
        log:printError("order event deduplication store failed", 'error = claimed);
        return;
    }
    if !claimed || (processedRuntimeEvents.hasKey(event.eventId) &&
        processedRuntimeEvents[event.eventId] == true) {
        boolean|error completed = isDurableEventCompleted(event.eventId);
        if completed is error {
            log:printError("order durable event status lookup failed", 'error = completed);
            return;
        }
        if completed {
            commitRecord(consumer, kafkaRecord);
        }
        pendingKafkaOffsets[event.eventId] = {
            topic: kafkaRecord.offset.partition.topic,
            partition: kafkaRecord.offset.partition.partition,
            offset: kafkaRecord.offset.offset
        };
        return;
    }
    if testFailurePoint == "AFTER_PROCESSING_CLAIM" &&
        (testFailureEventId == "" || testFailureEventId == event.eventId) {
        log:printError("test-only crash injection after durable processing claim");
        // The subprocess targets this container's PID 1. This is deliberately
        // only reachable through the disabled-by-default test configuration.
        os:Process|os:Error killResult = os:exec({value: "kill", arguments: ["-TERM", "1"]});
        return;
    }

    int attempt = 0;
    while attempt < consumerRetries {
        attempt += 1;
        if attempt > 1 {
            runtime:sleep(retryBackoffSeconds(attempt));
        }
        error? result = applyRuntimeEvent(event);
        if result is () {
            processedRuntimeEvents[event.eventId] = true;
            error? completed = completeDurableEvent(event.eventId);
            replayPendingEvents(event.orderId);
            commitRecord(consumer, kafkaRecord);
            return;
        }
        if result is error && result.message() == "PENDING_EVENT" {
            json[] pending = pendingEventsFor(event.orderId);
            pending.push(raw);
            pendingEvents[event.orderId] = pending;
            error? pendingPersisted = persistDurablePendingEvent(event.eventId, event.orderId, raw);
            if pendingPersisted is error {
                log:printError("order pending event persistence failed", 'error = pendingPersisted);
                return;
            }
            if testFailurePoint == "AFTER_PENDING_PERSIST" &&
                (testFailureEventId == "" || testFailureEventId == event.eventId) {
                log:printError("test-only crash injection after durable pending persistence");
                os:Process|os:Error killResult = os:exec({value: "kill", arguments: ["-TERM", "1"]});
                return;
            }
            commitRecord(consumer, kafkaRecord);
            return;
        }
    }
    checkParkAndCommit(consumer, kafkaRecord, "event processing exhausted retries", attempt);
}

function retryBackoffSeconds(int attempt) returns decimal {
    if attempt == 2 {
        return consumerRetryBackoffFirst;
    }
    return consumerRetryBackoffSecond;
}

function replayPendingEvents(string orderId) {
    lock {
        json[] pending = pendingEventsFor(orderId);
        if pending.length() == 0 {
            return;
        }

        json[] remaining = [];
        foreach json rawPending in pending {
            RuntimeEventEnvelope|error pendingEvent = rawPending.cloneWithType(RuntimeEventEnvelope);
            if pendingEvent is error {
                remaining.push(rawPending);
                continue;
            }
            error? result = applyRuntimeEvent(pendingEvent);
            if result is error {
                remaining.push(rawPending);
            } else {
                processedRuntimeEvents[pendingEvent.eventId] = true;
                error? completed = completeDurableEvent(pendingEvent.eventId);
                error? removed = removeDurablePendingEvent(pendingEvent.eventId);
                commitRecoveredPendingOffset(pendingEvent.eventId);
            }
        }
        if remaining.length() == 0 {
            if pendingEvents.hasKey(orderId) {
                _ = pendingEvents.remove(orderId);
            }
        } else {
            pendingEvents[orderId] = remaining;
        }
    }
}

function pendingEventsFor(string orderId) returns json[] {
    json[]? pending = pendingEvents[orderId];
    if pending is json[] {
        return pending;
    }
    return [];
}

function commitRecoveredPendingOffset(string eventId) {
    if !pendingKafkaOffsets.hasKey(eventId) {
        log:printWarn("recovered pending Kafka offset was not found for " + eventId);
        return;
    }
    PendingKafkaOffset? pendingOffset = pendingKafkaOffsets[eventId];
    if pendingOffset is () {
        log:printWarn("recovered pending Kafka offset was empty for " + eventId);
        return;
    }
    kafka:Consumer|error? consumerValue = orderConsumer;
    if consumerValue is kafka:Consumer {
        kafka:PartitionOffset committed = {
            partition: {
                topic: pendingOffset.topic,
                partition: pendingOffset.partition
            },
            offset: pendingOffset.offset + 1
        };
        kafka:Error? result = consumerValue->commitOffset([committed]);
        if result is kafka:Error {
            log:printError("recovered pending Kafka offset commit failed", 'error = result);
        }
    }
}

function applyRuntimeEvent(RuntimeEventEnvelope event) returns error? {
    Order? current = orders[event.orderId];
    if current is () {
        return error("order does not exist yet");
    }
    if event.eventType == "delivery.completed" && current.status != "OUT_FOR_DELIVERY" {
        return error("PENDING_EVENT");
    }
    Order|http:Response next = applyEvent(current, event.eventType);
    if next is http:Response {
        if next.statusCode == 409 && event.eventType == "payments.completed" &&
            current.restaurantAcceptedAt is () {
            return error("PENDING_EVENT");
        }
        if next.statusCode == 409 || next.statusCode == 400 {
            return ();
        }
        return error("order transition failed");
    }
    if next.version == current.version && next.status == current.status {
        return ();
    }
    Order|error atomicResult = applyAtomicTransition(current, next);
    if atomicResult is error {
        if atomicResult.message() == "STALE_TRANSITION" {
            log:printWarn("stale order event committed without publication");
            return ();
        }
        log:printError("atomic order transition failed for " + event.orderId +
            " event " + event.eventId, 'error = atomicResult);
        return atomicResult;
    }
    Order transitioned = atomicResult;
    orders[event.orderId] = transitioned;
    string orderTopic = transitioned.status == "CANCELLED" ? "orders.cancelled" :
        "orders." + transitioned.status.toLowerAscii();
    recordEvent(event.orderId, orderTopic, transitioned, event.eventId);
    if event.eventType != "restaurant.accepted" {
        error? orderPublished = publishDerivedOrderEvent(orderTopic, event, transitioned);
        if orderPublished is error {
            return orderPublished;
        }
    }
    if event.eventType == "restaurant.accepted" {
        error? paymentRequest = publishDerivedOrderEvent("payment.requested", event, transitioned);
        if paymentRequest is error {
            return paymentRequest;
        }
    }
    return ();
}

function publishDerivedOrderEvent(string eventType, RuntimeEventEnvelope eventSource, Order nextOrder) returns error? {
    string|error eventIdResult = derivedEventId(eventSource.eventId, eventType);
    if eventIdResult is error {
        return eventIdResult;
    }
    json envelope = {
        eventId: eventIdResult,
        eventType: eventType,
        occurredAt: time:utcToString(time:utcNow()),
        orderId: eventSource.orderId,
        correlationId: eventSource.correlationId,
        producerService: "order-service",
        data: {
            orderSummary: {
                customerId: nextOrder.customerId,
                restaurantId: nextOrder.restaurantId,
                total: nextOrder.total,
                currency: nextOrder.currency,
                deliveryAddress: nextOrder.deliveryAddress,
                driverId: nextOrder.driverId
            },
            payload: {paymentMethod: nextOrder.paymentMethod}
        }
    };
    return publishOrderEvent(eventType, nextOrder.orderId, envelope);
}

function commitRecord(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord) {
    kafka:PartitionOffset committed = {
        partition: kafkaRecord.offset.partition,
        offset: kafkaRecord.offset.offset + 1
    };
    kafka:Error? result = consumer->commitOffset([committed]);
    if result is kafka:Error {
        log:printError("order Kafka offset commit failed", 'error = result);
    }
}

function checkParkAndCommit(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord,
        string reason, int attempts) {
    string topic = kafkaRecord.offset.partition.topic;
    string key = recordKey(kafkaRecord);
    string rawPayload = recordPayload(kafkaRecord);
    json dlqEnvelope = {
        originalTopic: topic,
        key: key,
        rawPayload: rawPayload,
        'error: reason,
        attempts: attempts,
        consumerGroup: "order-service",
        failedAt: time:utcToString(time:utcNow())
    };
    error? published = publishOrderEvent(topic + ".dlq", "order-service", dlqEnvelope);
    if published is error {
        log:printError("order Kafka DLQ publication failed", 'error = published);
        return;
    }

    commitRecord(consumer, kafkaRecord);
}

function bytesAsString(byte[] value) returns string {
    string|error decoded = str:fromBytes(value);
    return decoded is string ? decoded : "";
}

function recordKey(kafka:AnydataConsumerRecord kafkaRecord) returns string {
    anydata? key = kafkaRecord?.key;
    return key is byte[] ? bytesAsString(key) : "";
}

function recordPayload(kafka:AnydataConsumerRecord kafkaRecord) returns string {
    anydata payload = kafkaRecord.value;
    return payload is byte[] ? bytesAsString(payload) : "";
}

function isRuntimeTopic(string eventType) returns boolean {
    foreach string topic in BASE_RUNTIME_TOPICS {
        if topic == eventType {
            return true;
        }
    }
    return false;
}

final string[] BASE_RUNTIME_TOPICS = [
    "orders.created", "orders.confirmed", "orders.preparing", "orders.ready",
    "orders.out_for_delivery", "orders.delivered", "orders.cancelled",
    "orders.autocancelled", "payments.completed", "payment.requested",
    "payments.failed", "payments.cancelled", "payments.refunded",
    "restaurant.accepted", "restaurant.rejected", "restaurant.preparing",
    "restaurant.ready", "delivery.assigned", "delivery.picked_up",
    "delivery.not_assigned", "delivery.completed", "delivery.cancelled",
    "delivery.failed"
];
