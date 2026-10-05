import ballerinax/kafka;
import ballerina/log;
import ballerina/task;
import ballerina/lang.'string as str;

configurable boolean kafkaRuntimeEnabled = false;
configurable string kafkaBootstrap = "kafka:9092";

final string[] dlqTopics = [
    "orders.created.dlq", "orders.cancelled.dlq", "orders.confirmed.dlq",
    "orders.preparing.dlq", "orders.ready.dlq", "orders.out_for_delivery.dlq",
    "orders.delivered.dlq", "orders.autocancelled.dlq", "restaurant.accepted.dlq",
    "restaurant.rejected.dlq", "restaurant.preparing.dlq", "restaurant.ready.dlq",
    "payment.requested.dlq", "payments.completed.dlq", "payments.failed.dlq",
    "payments.refunded.dlq", "payments.cancelled.dlq", "delivery.assigned.dlq",
    "delivery.not_assigned.dlq", "delivery.picked_up.dlq", "delivery.completed.dlq",
    "delivery.cancelled.dlq", "delivery.failed.dlq"
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

type DlqEnvelope record {|
    string originalTopic;
    string key;
    string rawPayload;
    string 'error;
    int attempts;
    string consumerGroup;
    string failedAt;
|};

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

function hasKafkaKey(anydata? key) returns boolean {
    return key is byte[] && key.length() > 0;
}

function startKafkaRuntime() returns error? {
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

class DlqConsumerJob {
    *task:Job;

    public function execute() {
        kafka:Consumer|error? current = dlqConsumer;
        if current is kafka:Consumer {
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
}

function handleDlqRecord(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord) {
    string topic = kafkaRecord.offset.partition.topic;
    int partition = kafkaRecord.offset.partition.partition;
    int offset = kafkaRecord.offset.offset;
    anydata? kafkaKey = kafkaRecord?.key;
    boolean keyPresent = hasKafkaKey(kafkaKey);
    log:printInfo("admin DLQ record received", fields = {
        topic: topic, partition: partition, offset: offset,
        keyPresent: keyPresent ? "yes" : "no"
    });
    if kafkaRecord.value is byte[] {
        byte[] bytes = <byte[]>kafkaRecord.value;
        string|error raw = str:fromBytes(bytes);
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
        json|error original = envelope.rawPayload.fromJsonString();
        string? eventId = extractEventId(original);
        error? persisted = persistDlq({
            dlqTopic: dlqTopicIdentity(topic),
            dlqPartition: partition,
            dlqOffset: offset,
            originalTopic: envelope.originalTopic,
            key: envelope.key,
            eventId: eventId,
            consumerGroup: envelope.consumerGroup,
            rawPayload: envelope.rawPayload,
            'error: envelope.'error,
            attempts: envelope.attempts,
            receivedAt: envelope.failedAt
        });
        if persisted is error {
            log:printError("admin DLQ persistence failed; retrying", 'error = persisted,
                fields = {topic: topic, partition: partition, offset: offset});
            return;
        }
        log:printInfo("admin DLQ record persisted", fields = {
            topic: topic, partition: partition, offset: offset,
            eventId: eventId ?: "null"
        });
        kafka:Error? committed = consumer->commitOffset([{
            partition: kafkaRecord.offset.partition,
            offset: offset + 1
        }]);
        if committed is error {
            log:printError("admin DLQ offset commit failed; record will be retried",
                'error = committed,
                fields = {topic: topic, partition: partition, offset: offset});
        }
        return;
    }
    log:printError("admin DLQ record has no byte value; retrying",
        fields = {topic: topic, partition: partition, offset: offset});
}
