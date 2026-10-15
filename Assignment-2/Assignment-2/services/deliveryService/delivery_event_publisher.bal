import ballerina/uuid;
import ballerinax/kafka;

configurable boolean kafkaEnabled = false;
configurable string kafkaBootstrapServers = kafka:DEFAULT_URL;

const string DELIVERY_ASSIGNED_TOPIC = "delivery.assigned";
const string DELIVERY_COMPLETED_TOPIC = "delivery.completed";

type DomainEvent record {|
    readonly string eventId;
    string eventType;
    string aggregateId;
    string 'source;
    int schemaVersion;
    string occurredAt;
    json payload;
|};

final kafka:Producer? deliveryEventProducer = kafkaEnabled ? checkpanic new (kafkaBootstrapServers, {
        clientId: "delivery-service-producer",
        acks: kafka:ACKS_ALL,
        retryCount: 5,
        enableIdempotence: true
}) : ();

function stop() returns error? {
    kafka:Producer? eventProducer = deliveryEventProducer;
    if eventProducer is kafka:Producer {
        check eventProducer->close();
    }
}

isolated function publishDeliveryAssignedEvent(Delivery delivery) returns error? {
    check publishDeliveryEvent(DELIVERY_ASSIGNED_TOPIC, delivery);
}

isolated function publishDeliveryCompletedEvent(Delivery delivery) returns error? {
    if delivery.status == DELIVERED {
        check publishDeliveryEvent(DELIVERY_COMPLETED_TOPIC, delivery);
    }
}

isolated function publishDeliveryEvent(string topic, Delivery delivery) returns error? {
    kafka:Producer? eventProducer = deliveryEventProducer;
    if eventProducer is kafka:Producer {
        DomainEvent domainEvent = {
            eventId: uuid:createType4AsString(),
            eventType: topic,
            aggregateId: delivery.orderId,
            'source: "delivery_service",
            schemaVersion: 1,
            occurredAt: delivery.updatedAt,
            payload: delivery
        };
        check eventProducer->send({topic, key: delivery.orderId.toBytes(), value: domainEvent});
    }
}
