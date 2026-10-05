// Kafka consumer for every dead-letter (`.dlq`) topic.
//
// Each DLQ record is stored in `dlq_log` (see `dlq_store.bal`) and then
// committed. A record that cannot be decoded, parsed or stored is logged and
// left uncommitted.

import ballerina/lang.'string as str;
import ballerina/log;
import ballerina/task;
import ballerinax/kafka;

// Kafka stays off unless the Docker runtime enables it, so unit tests need no broker.
configurable boolean kafkaRuntimeEnabled = false;
configurable string kafkaBootstrap = "kafka:9092";

// The `.dlq` twin of every base topic.
final string[] dlqTopics = [
    "orders.created.dlq",
    "orders.cancelled.dlq",
    "orders.confirmed.dlq",
    "orders.preparing.dlq",
    "orders.ready.dlq",
    "orders.out_for_delivery.dlq",
    "orders.delivered.dlq",
    "orders.autocancelled.dlq",
    "restaurant.accepted.dlq",
    "restaurant.rejected.dlq",
    "restaurant.preparing.dlq",
    "restaurant.ready.dlq",
    "payment.requested.dlq",
    "payments.completed.dlq",
    "payments.failed.dlq",
    "payments.refunded.dlq",
    "payments.cancelled.dlq",
    "delivery.assigned.dlq",
    "delivery.not_assigned.dlq",
    "delivery.picked_up.dlq",
    "delivery.completed.dlq",
    "delivery.cancelled.dlq",
    "delivery.failed.dlq"
];

final kafka:ConsumerConfiguration dlqConsumerConfiguration = {
    groupId: "admin-service",
    topics: dlqTopics,
    offsetReset: "earliest",
    autoCommit: false,
    pollingInterval: 1,
    maxPollRecords: 10
};

kafka:Consumer|error? dlqConsumer = ();

// What a failing consumer writes to a `.dlq` topic.
type DlqEnvelope record {|
    string originalTopic;
    string key;
    string rawPayload;
    string 'error;
    int attempts;
    string consumerGroup;
    string failedAt;
|};

// Creates the consumer and schedules the polling job when Kafka is enabled.
function startDlqConsumer() returns error? {
    if !kafkaRuntimeEnabled {
        return;
    }
    kafka:Consumer|error consumer = new (kafkaBootstrap, dlqConsumerConfiguration);
    if consumer is error {
        return consumer;
    }
    dlqConsumer = consumer;
    _ = check task:scheduleJobRecurByFrequency(new DlqConsumerJob(), 1);
}

// Polls one batch of DLQ records and handles each one.
class DlqConsumerJob {
    *task:Job;

    public function execute() {
        kafka:Consumer|error? current = dlqConsumer;
        if current !is kafka:Consumer {
            return;
        }
        kafka:AnydataConsumerRecord[]|kafka:Error records = current->poll(1);
        if records is kafka:Error {
            log:printError("admin DLQ poll failed", 'error = records);
            return;
        }
        foreach kafka:AnydataConsumerRecord kafkaRecord in records {
            handleDlqRecord(current, kafkaRecord);
        }
    }
}

// Stores one DLQ record in `dlq_log`, then commits it.
function handleDlqRecord(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord) {
    string topic = kafkaRecord.offset.partition.topic;
    int partition = kafkaRecord.offset.partition.partition;
    int offset = kafkaRecord.offset.offset;
    anydata? kafkaKey = kafkaRecord?.key;
    log:printInfo("admin DLQ record received", fields = {
                topic: topic,
                partition: partition,
                offset: offset,
                keyPresent: hasKafkaKey(kafkaKey) ? "yes" : "no"
            });

    anydata value = kafkaRecord.value;
    if value !is byte[] {
        log:printError("admin DLQ record has no byte value; retrying",
                fields = {topic: topic, partition: partition, offset: offset});
        return;
    }

    string|error raw = str:fromBytes(value);
    if raw is error {
        log:printError("admin DLQ record decode failed; retrying", 'error = raw,
                fields = {topic: topic, partition: partition, offset: offset});
        return;
    }

    DlqEnvelope|error envelope = parseDlqEnvelope(raw);
    if envelope is error {
        log:printError("admin DLQ envelope parse failed; retrying", 'error = envelope,
                fields = {topic: topic, partition: partition, offset: offset});
        return;
    }

    DlqDocument document = toDlqDocument(topic, partition, offset, envelope);
    error? persisted = persistDlq(document);
    if persisted is error {
        log:printError("admin DLQ persistence failed; retrying", 'error = persisted,
                fields = {topic: topic, partition: partition, offset: offset});
        return;
    }
    log:printInfo("admin DLQ record persisted", fields = {
                topic: topic,
                partition: partition,
                offset: offset,
                eventId: document.eventId ?: "null"
            });

    kafka:Error? committed = consumer->commitOffset([
        {
            partition: kafkaRecord.offset.partition,
            offset: offset + 1
        }
    ]);
    if committed is error {
        log:printError("admin DLQ offset commit failed; record will be retried",
                'error = committed,
                fields = {topic: topic, partition: partition, offset: offset});
    }
}

// Builds the `dlq_log` document for a record read at topic/partition/offset.
// `eventId` comes from the original payload when it is JSON with a string `eventId`.
function toDlqDocument(string topic, int partition, int offset, DlqEnvelope envelope) returns DlqDocument {
    json|error originalPayload = envelope.rawPayload.fromJsonString();
    return {
        dlqTopic: dlqTopicIdentity(topic),
        dlqPartition: partition,
        dlqOffset: offset,
        originalTopic: envelope.originalTopic,
        key: envelope.key,
        eventId: extractEventId(originalPayload),
        consumerGroup: envelope.consumerGroup,
        rawPayload: envelope.rawPayload,
        'error: envelope.'error,
        attempts: envelope.attempts,
        receivedAt: envelope.failedAt
    };
}

// The topic the record was read from, stored as-is (no extra `.dlq` suffix).
function dlqTopicIdentity(string receivedTopic) returns string {
    return receivedTopic;
}

function parseDlqEnvelope(string raw) returns DlqEnvelope|error {
    json|error parsed = raw.fromJsonString();
    if parsed is error {
        return parsed;
    }
    return parsed.cloneWithType(DlqEnvelope);
}

// True when the Kafka key is a non-empty byte array.
function hasKafkaKey(anydata? key) returns boolean {
    return key is byte[] && key.length() > 0;
}
