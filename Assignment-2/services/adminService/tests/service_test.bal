import ballerina/http;
import ballerina/test;

http:Client testClient = check new ("http://localhost:9090");

// Health

@test:Config {}
function testHealthReturnsUp() {
    json|error response = testClient->/admin/health;
    test:assertEquals(response, {status: "UP", 'service: "admin"});
}

@test:Config {}
function testHealthReturnsStatus200() returns error? {
    http:Response response = check testClient->/admin/health;
    test:assertEquals(response.statusCode, 200);
    json healthPayload = check response.getJsonPayload();
    test:assertEquals(healthPayload, {status: "UP", 'service: "admin"});
}

// Replay helpers

@test:Config {}
function testReplayTopicValidation() {
    test:assertTrue(isReplayableTopic("restaurant.accepted"));
    test:assertFalse(isReplayableTopic("restaurant.accepted.dlq"));
    test:assertFalse(isReplayableTopic(""));
}

@test:Config {}
function testReplayPreservesEventPayload() returns error? {
    json payload = check parseReplayPayload("{\"eventId\":\"event-1\",\"eventType\":\"restaurant.accepted\"}");
    test:assertEquals(payload.eventId, "event-1");
    test:assertEquals(payload.eventType, "restaurant.accepted");
}

// DLQ document and location identity

@test:Config {}
function testDlqDocumentDefaultsToParked() {
    DlqDocument document = sampleDocument(0, 10, "order-service");
    test:assertEquals(document.status, "PARKED");
    test:assertEquals(document.replayedAt, ());
}

@test:Config {}
function testUnparseableDlqPayloadsRemainDistinct() {
    string? first = extractEventId("{not-json}".fromJsonString());
    string? second = extractEventId("also-not-json".fromJsonString());
    test:assertEquals(first, ());
    test:assertEquals(second, ());
    test:assertNotEquals(dlqLocationKey("restaurant.accepted.dlq", 0, 10),
            dlqLocationKey("restaurant.accepted.dlq", 0, 11));
}

@test:Config {}
function testSameEventIdCanBeAuditedForDifferentConsumerGroups() {
    DlqDocument first = sampleDocument(0, 10, "order-service");
    DlqDocument second = sampleDocument(1, 10, "another-consumer");
    test:assertEquals(first.eventId, second.eventId);
    test:assertNotEquals(first.consumerGroup, second.consumerGroup);
    test:assertNotEquals(dlqLocationKey(first.dlqTopic, first.dlqPartition, first.dlqOffset),
            dlqLocationKey(second.dlqTopic, second.dlqPartition, second.dlqOffset));
}

@test:Config {}
function testDlqRedeliveryUsesSameLocationIdentity() {
    test:assertEquals(dlqLocationKey("restaurant.accepted.dlq", 2, 44),
            dlqLocationKey("restaurant.accepted.dlq", 2, 44));
}

@test:Config {}
function testDlqTopicIdentityDoesNotAppendDlqSuffix() {
    test:assertEquals(dlqTopicIdentity("orders.created.dlq"), "orders.created.dlq");
    test:assertNotEquals(dlqTopicIdentity("orders.created.dlq"), "orders.created.dlq.dlq");
}

// Consumer helpers

@test:Config {}
function testDlqEnvelopeParsingUsesJsonConversion() returns error? {
    DlqEnvelope envelope = check parseDlqEnvelope(
            "{\"originalTopic\":\"orders.created\",\"key\":\"order-1\","
            + "\"rawPayload\":\"{not-json}\",\"error\":\"failure\","
            + "\"attempts\":1,\"consumerGroup\":\"order-service\","
            + "\"failedAt\":\"2026-10-04T00:00:00Z\"}");
    test:assertEquals(envelope.originalTopic, "orders.created");
    error|DlqEnvelope malformed = parseDlqEnvelope("{not-json}");
    test:assertTrue(malformed is error);
}

@test:Config {}
function testNullKafkaKeyIsAccepted() {
    test:assertFalse(hasKafkaKey(()));
    test:assertFalse(hasKafkaKey([]));
    test:assertTrue(hasKafkaKey("order-1".toBytes()));
}

@test:Config {}
function testDlqDocumentTakesEventIdFromPayload() {
    DlqEnvelope envelope = {
        originalTopic: "orders.created",
        key: "order-1",
        rawPayload: "{\"eventId\":\"evt-9\"}",
        'error: "failure",
        attempts: 3,
        consumerGroup: "order-service",
        failedAt: "2026-10-05T00:00:00Z"
    };
    DlqDocument document = toDlqDocument("orders.created.dlq", 0, 7, envelope);
    test:assertEquals(document.eventId, "evt-9");
    test:assertEquals(document.dlqTopic, "orders.created.dlq");
    test:assertEquals(document.receivedAt, "2026-10-05T00:00:00Z");
}

function sampleDocument(int partition, int offset, string consumerGroup) returns DlqDocument {
    return {
        dlqTopic: "restaurant.accepted.dlq",
        dlqPartition: partition,
        dlqOffset: offset,
        originalTopic: "restaurant.accepted",
        key: "order-1",
        eventId: "same-event",
        consumerGroup: consumerGroup,
        rawPayload: "{\"eventId\":\"same-event\"}",
        'error: "failure",
        attempts: 1,
        receivedAt: "now"
    };
}
