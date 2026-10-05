import ballerinax/kafka;
import ballerina/log;

configurable string kafkaBootstrap = "kafka:9092";
configurable string orderConsumerGroup = "order-service";

final kafka:ProducerConfiguration producerConfiguration = {
    clientId: "order-service",
    acks: "all",
    retryCount: 3
};
kafka:Producer|error? orderProducer = ();

public function publishOrderEvent(string topic, string orderId, json payload) returns error? {
    return publishOrderEventInternal(topic, orderId, payload, true, true);
}

function publishOrderEventInternal(string topic, string orderId, json payload, boolean recordOutbox,
        boolean asynchronousFlush = false)
        returns error? {
    if recordOutbox && payload is map<json> {
        json? rawEventId = payload["eventId"];
        if rawEventId is string {
            check addDurableOutbox(rawEventId, topic, orderId, payload);
        }
    }
    kafka:Producer|error producer = ensureProducer();
    if producer is error {
        return producer;
    }
    check producer->send({
        topic: topic,
        key: orderId.toBytes(),
        value: payload.toJsonString().toBytes()
    });
    if asynchronousFlush {
        string? eventId = ();
        if payload is map<json> && payload["eventId"] is string {
            eventId = <string>payload["eventId"];
        }
        _ = start flushAndMarkOutboxPublishedAsync(producer, eventId);
        return;
    }
    check producer->'flush();
    if recordOutbox && payload is map<json> && payload["eventId"] is string {
        _ = start markOutboxPublishedAsync(<string>payload["eventId"]);
    }
}

function flushAndMarkOutboxPublishedAsync(kafka:Producer producer, string? eventId) returns error? {
    error? flushed = producer->'flush();
    if flushed is error {
        log:printWarn("Kafka flush failed after asynchronous publication", 'error = flushed);
        return flushed;
    }
    if eventId is string {
        return markDurableOutboxPublished(eventId);
    }
}

function markOutboxPublishedAsync(string eventId) returns error? {
    error? marked = markDurableOutboxPublished(eventId);
    if marked is error {
        log:printWarn("outbox status update failed after publication", 'error = marked);
        return marked;
    }
}

function ensureProducer() returns kafka:Producer|error {
    kafka:Producer|error? current = orderProducer;
    if current is kafka:Producer {
        return current;
    }
    if current is error {
        return current;
    }
    kafka:Producer|error created = new (kafkaBootstrap, producerConfiguration);
    orderProducer = created;
    return created;
}
