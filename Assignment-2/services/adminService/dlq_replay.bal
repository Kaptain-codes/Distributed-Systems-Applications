// DLQ replay: re-sends a parked payload, unchanged, to its original topic.
//
// A payload that carries an `eventId` is replayed at most once per
// (topic, eventId); the second request returns `alreadyReplayed: true`.
// A payload without an `eventId` is sent every time it is requested.

import ballerinax/kafka;

// Body of `POST /admin/dlq/replay`.
type DlqReplayRequest record {|
    string originalTopic;
    string key = "";
    string rawPayload;
|};

final kafka:ProducerConfiguration replayProducerConfiguration = {
    clientId: "admin-service-dlq-replay",
    acks: "all",
    retryCount: 3
};

// Created on first use.
kafka:Producer|error? replayProducer = ();

# Replays one DLQ payload.
#
# Steps: check the topic, parse the payload, skip if this event was already
# replayed, record the replay as PARKED, send it, then mark it REPLAYED.
#
# + request - topic, Kafka key and raw payload to send
# + return - the replay result, or an error (returned to the caller as HTTP 500)
function replayDlqRecord(DlqReplayRequest request) returns json|error {
    if !isReplayableTopic(request.originalTopic) {
        return error("INVALID_TOPIC: originalTopic must be a base Kafka topic");
    }
    json payload = check parseReplayPayload(request.rawPayload);
    string? eventId = extractEventId(payload);

    if eventId is string {
        boolean alreadyReplayed = check isReplayCompleted(request.originalTopic, eventId);
        if alreadyReplayed {
            return {
                replayed: false,
                alreadyReplayed: true,
                topic: request.originalTopic,
                key: request.key,
                payload: payload
            };
        }
        check ensureDlqReplayRecord(request.originalTopic, eventId, request.key, request.rawPayload);
    }

    kafka:Producer|error producer = ensureReplayProducer();
    if producer is error {
        return error("KAFKA_UNAVAILABLE: " + producer.message());
    }
    check producer->send({
        topic: request.originalTopic,
        key: request.key.toBytes(),
        value: request.rawPayload.toBytes()
    });
    check producer->'flush();

    if eventId is string {
        check markDlqReplayed(request.originalTopic, eventId);
    }
    return {replayed: true, topic: request.originalTopic, key: request.key, payload: payload};
}

// A topic can be replayed to if it is non-empty, contains a dot,
// and is not itself a `.dlq` topic.
function isReplayableTopic(string topic) returns boolean {
    if topic.length() == 0 || topic.endsWith(".dlq") {
        return false;
    }
    return topic.indexOf(".") > 0;
}

function parseReplayPayload(string rawPayload) returns json|error {
    json|error payload = rawPayload.fromJsonString();
    if payload is error {
        return error("INVALID_PAYLOAD: rawPayload must contain valid JSON");
    }
    return payload;
}

// Returns the shared replay producer, creating it on first use.
// A failed creation is remembered and returned on later calls.
function ensureReplayProducer() returns kafka:Producer|error {
    kafka:Producer|error? current = replayProducer;
    if current is kafka:Producer {
        return current;
    }
    if current is error {
        return current;
    }
    kafka:Producer|error created = new (kafkaBootstrap, replayProducerConfiguration);
    replayProducer = created;
    return created;
}
