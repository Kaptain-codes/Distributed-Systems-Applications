import ballerina/http;
import ballerinax/kafka;

configurable int port = 9090;

type DlqRecord record {|
    string topic;
    string rawPayload;
    string 'error;
    int attempts;
    string receivedAt;
|};

type DlqReplayRequest record {|
    string originalTopic;
    string key = "";
    string rawPayload;
|};

map<DlqRecord> dlq = {};
kafka:Producer|error? replayProducer = ();
final kafka:ProducerConfiguration replayProducerConfiguration = {
    clientId: "admin-service-dlq-replay",
    acks: "all",
    retryCount: 3
};

service /admin on new http:Listener(port) {
    function init() returns error? {
        check initDurableState();
        return startKafkaRuntime();
    }

    resource function get health() returns json {
        return {status: "UP", 'service: "admin"};
    }

    resource function get dlq() returns json|error {
        if durableStateEnabled {
            return check listDurableDlq();
        }
        return dlq.toJson();
    }

    resource function post dlq/replay(@http:Payload DlqReplayRequest request) returns json|error {
        lock {
            if !isReplayableTopic(request.originalTopic) {
                return error("INVALID_TOPIC: originalTopic must be a base Kafka topic");
            }
            json payload = check parseReplayPayload(request.rawPayload);
            if payload is map<json> && payload["eventId"] is string {
                string eventId = <string>payload["eventId"];
                boolean|error replayed = isReplayCompleted(request.originalTopic, eventId);
                if replayed is error {
                    return replayed;
                }
                if replayed {
                    return {replayed: false, alreadyReplayed: true, topic: request.originalTopic,
                        key: request.key, payload: payload};
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
            if payload is map<json> && payload["eventId"] is string {
                check markDlqReplayed(request.originalTopic, <string>payload["eventId"]);
            }
            return {replayed: true, topic: request.originalTopic, key: request.key, payload: payload};
        }
    }

    resource function get reports/restaurants() returns json {
        return {restaurants: [], generatedAt: "UTC"};
    }

    resource function get reports/restaurants/[string restaurantId]() returns json {
        return {restaurantId: restaurantId, placed: 0, confirmed: 0, rejected: 0, cancelled: 0, delivered: 0};
    }

    resource function get reports/deliveries() returns json {
        return {deliveries: [], generatedAt: "UTC"};
    }
}

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
