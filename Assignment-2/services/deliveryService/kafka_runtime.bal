import ballerinax/kafka;
import ballerina/lang.'string as str;
import ballerina/log;
import ballerina/task;
import ballerina/time;
import ballerina/uuid;

configurable boolean kafkaRuntimeEnabled = false;
configurable string kafkaBootstrap = "kafka:9092";

type DeliveryEvent record {|
    string eventId;
    string eventType;
    string orderId;
    string correlationId;
    json occurredAt = ();
    string producerService = "";
    json data = {};
|};

final kafka:ConsumerConfiguration deliveryConsumerConfiguration = {
    groupId: "delivery-service",
    topics: ["orders.ready", "orders.cancelled", "orders.autocancelled"],
    offsetReset: "earliest",
    autoCommit: false,
    pollingInterval: 1,
    maxPollRecords: 10
};

final kafka:ProducerConfiguration deliveryProducerConfiguration = {
    clientId: "delivery-service",
    acks: "all",
    retryCount: 3
};

kafka:Consumer|error? deliveryConsumer = ();
kafka:Producer|error? deliveryProducer = ();
map<boolean> deliveryProcessedEvents = {};
map<DeliveryEvent> orderEvents = {};

function startDeliveryKafkaRuntime() returns error? {
    if !kafkaRuntimeEnabled {
        return;
    }
    if !durableStateEnabled && drivers.length() == 0 {
        drivers["demo-driver"] = {driverId: "demo-driver", name: "Demo Driver", status: "AVAILABLE"};
    }
    kafka:Consumer|error consumer = new (kafkaBootstrap, deliveryConsumerConfiguration);
    if consumer is error {
        return consumer;
    }
    deliveryConsumer = consumer;
    _ = check task:scheduleJobRecurByFrequency(new DeliveryKafkaJob(), 1);
}

class DeliveryKafkaJob {
    *task:Job;

    public function execute() {
        kafka:Consumer|error? current = deliveryConsumer;
        if current is kafka:Consumer {
            kafka:AnydataConsumerRecord[]|kafka:Error records = current->poll(1);
            if records is kafka:Error {
                log:printError("delivery Kafka poll failed", 'error = records);
                return;
            }
            foreach kafka:AnydataConsumerRecord kafkaRecord in records {
                handleDeliveryRecord(current, kafkaRecord);
            }
        }
    }
}

function handleDeliveryRecord(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord) {
    if kafkaRecord.value !is byte[] {
        commitDeliveryRecord(consumer, kafkaRecord);
        return;
    }
    string|error raw = str:fromBytes(<byte[]>kafkaRecord.value);
    if raw is error {
        commitDeliveryRecord(consumer, kafkaRecord);
        return;
    }
    json|error parsed = raw.fromJsonString();
    if parsed is error {
        commitDeliveryRecord(consumer, kafkaRecord);
        return;
    }
    DeliveryEvent|error event = parsed.cloneWithType(DeliveryEvent);
    if event is error {
        commitDeliveryRecord(consumer, kafkaRecord);
        return;
    }
    boolean|error processed = dbEventProcessed(event.eventId);
    if processed is error {
        log:printError("delivery event deduplication lookup failed", 'error = processed);
        return;
    }
    if processed {
        commitDeliveryRecord(consumer, kafkaRecord);
        return;
    }
    if event.eventType == "orders.ready" {
        orderEvents[event.orderId] = event;
        Delivery|error? existing = dbFindDelivery(event.orderId);
        if existing is error {
            log:printError("delivery lookup failed while assigning order", 'error = existing);
            return;
        }
        if existing is Delivery && existing.status != "CANCELLED" {
            error? marked = dbMarkEvent(event.eventId);
            if marked is error { log:printError("delivery event mark failed", 'error = marked); }
            commitDeliveryRecord(consumer, kafkaRecord);
            return;
        }
        Driver|error? selected = dbAvailableDriver();
        string? driverId = selected is Driver ? selected.driverId : ();
        if driverId is string {
            string now = time:utcToString(time:utcNow());
            Delivery delivery = {
                deliveryId: uuid:createType4AsString(), orderId: event.orderId,
                pickupAddress: "Demo Restaurant", deliveryAddress: "Demo Address",
                driverId: driverId, status: "ASSIGNED", createdAt: now, updatedAt: now
            };
            boolean|error created = dbCreateDeliveryIfAbsent(delivery);
            if created is error {
                error? released = dbSetDriverStatus(driverId, "AVAILABLE");
                if released is error {
                    log:printError("failed to release driver after assignment failure",
                        'error = released);
                }
                log:printError("delivery assignment persistence failed", 'error = created);
                return;
            }
            if created {
                error? assigned = publishDeliveryEvent("delivery.assigned", event, delivery);
                if assigned is error {
                    log:printError("delivery assignment publication failed", 'error = assigned);
                    return;
                }
            } else {
                error? released = dbSetDriverStatus(driverId, "AVAILABLE");
                if released is error {
                    log:printError("duplicate delivery driver release failed", 'error = released);
                }
            }
        } else {
            error? unavailable = publishDeliveryEvent("delivery.not_assigned", event,
                {orderId: event.orderId, reason: "NO_DRIVER"});
            if unavailable is error {
                log:printError("delivery failure publication failed", 'error = unavailable);
                return;
            }
        }
    } else if event.eventType == "orders.cancelled" || event.eventType == "orders.autocancelled" {
        Delivery|error? delivery = dbFindDelivery(event.orderId);
        if delivery is Delivery {
            delivery.status = "CANCELLED";
            error? saved = dbSaveDelivery(delivery);
            if saved is error { log:printError("delivery cancellation persistence failed", 'error = saved); }
        }
    }
    error? marked = dbMarkEvent(event.eventId);
    if marked is error { log:printError("delivery event mark failed", 'error = marked); }
    commitDeliveryRecord(consumer, kafkaRecord);
}

function publishDeliveryEvent(string topic, DeliveryEvent sourceEvent, json payload) returns error? {
    kafka:Producer|error producer = ensureDeliveryProducer();
    if producer is error {
        return producer;
    }
    json|error summaryResult = sourceEvent.data.orderSummary;
    if summaryResult is error {
        return summaryResult;
    }
    json summary = summaryResult;
    json envelope = {
        eventId: uuid:createType4AsString(),
        eventType: topic,
        occurredAt: time:utcToString(time:utcNow()),
        orderId: sourceEvent.orderId,
        correlationId: sourceEvent.correlationId,
        producerService: "delivery-service",
        data: {orderSummary: summary, payload: payload}
    };
    string raw = envelope.toJsonString();
    check producer->send({topic: topic, key: sourceEvent.orderId.toBytes(), value: raw.toBytes()});
    check producer->'flush();
}

function publishManualDeliveryEvent(string orderId, string topic, json payload) returns error? {
    DeliveryEvent? sourceEvent = orderEvents[orderId];
    if sourceEvent is () {
        return error("orders.ready event is not available");
    }
    return publishDeliveryEvent(topic, sourceEvent, payload);
}

function ensureDeliveryProducer() returns kafka:Producer|error {
    kafka:Producer|error? current = deliveryProducer;
    if current is kafka:Producer {
        return current;
    }
    if current is error {
        return current;
    }
    kafka:Producer|error created = new (kafkaBootstrap, deliveryProducerConfiguration);
    deliveryProducer = created;
    return created;
}

function commitDeliveryRecord(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord) {
    kafka:PartitionOffset committed = {
        partition: kafkaRecord.offset.partition,
        offset: kafkaRecord.offset.offset + 1
    };
    kafka:Error? result = consumer->commitOffset([committed]);
    if result is kafka:Error {
        log:printError("delivery Kafka offset commit failed", 'error = result);
    }
}
