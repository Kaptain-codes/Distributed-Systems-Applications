import ballerinax/kafka;
import ballerina/lang.'string as str;
import ballerina/log;
import ballerina/task;
import ballerina/time;
import ballerina/uuid;

configurable boolean kafkaRuntimeEnabled = false;
configurable string kafkaBootstrap = "kafka:9092";

type RestaurantEvent record {|
    string eventId;
    string eventType;
    string orderId;
    string correlationId;
    json occurredAt = ();
    string producerService = "";
    json data = {};
|};

type OrderPayload record {|
    string orderId;
    string restaurantId;
    OrderItemPayload[] items;
    json...;
|};

type OrderItemPayload record {|
    string menuItemId;
    string name = "";
    decimal unitPrice = 0;
    int qty;
|};

final kafka:ConsumerConfiguration restaurantConsumerConfiguration = {
    groupId: "restaurant-service",
    topics: ["orders.created", "orders.confirmed", "orders.preparing",
        "orders.cancelled", "orders.autocancelled"],
    offsetReset: "earliest",
    autoCommit: false,
    pollingInterval: 1,
    maxPollRecords: 10
};

final kafka:ProducerConfiguration restaurantProducerConfiguration = {
    clientId: "restaurant-service",
    acks: "all",
    retryCount: 3
};

kafka:Consumer|error? restaurantConsumer = ();
kafka:Producer|error? restaurantProducer = ();
map<boolean> restaurantProcessedEvents = {};

function startRestaurantKafkaRuntime() returns error? {
    if !kafkaRuntimeEnabled {
        return;
    }
    kafka:Consumer|error consumer = new (kafkaBootstrap, restaurantConsumerConfiguration);
    if consumer is error {
        return consumer;
    }
    restaurantConsumer = consumer;
    _ = check task:scheduleJobRecurByFrequency(new RestaurantKafkaJob(), 1);
}

class RestaurantKafkaJob {
    *task:Job;

    public function execute() {
        kafka:Consumer|error? current = restaurantConsumer;
        if current is kafka:Consumer {
            kafka:AnydataConsumerRecord[]|kafka:Error records = current->poll(1);
            if records is kafka:Error {
                log:printError("restaurant Kafka poll failed", 'error = records);
                return;
            }
            foreach kafka:AnydataConsumerRecord kafkaRecord in records {
                log:printInfo("restaurant Kafka record received: " +
                    kafkaRecord.offset.partition.topic + ":" +
                    kafkaRecord.offset.offset.toString());
                handleRestaurantRecord(current, kafkaRecord);
            }
        }
    }
}

function handleRestaurantRecord(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord) {
    if kafkaRecord.value !is byte[] {
        commitRestaurantRecord(consumer, kafkaRecord);
        return;
    }
    byte[] bytes = <byte[]>kafkaRecord.value;
    string|error raw = str:fromBytes(bytes);
    if raw is error {
        commitRestaurantRecord(consumer, kafkaRecord);
        return;
    }
    json|error parsed = raw.fromJsonString();
    if parsed is error {
        commitRestaurantRecord(consumer, kafkaRecord);
        return;
    }
    RestaurantEvent|error event = parsed.cloneWithType(RestaurantEvent);
    if event is error {
        log:printError("restaurant event envelope conversion failed", 'error = event);
        commitRestaurantRecord(consumer, kafkaRecord);
        return;
    }
    if restaurantProcessedEvents[event.eventId] == true {
        commitRestaurantRecord(consumer, kafkaRecord);
        return;
    }
    log:printInfo("restaurant event envelope decoded: " + event.eventType + ":" + event.orderId);
    if event.eventType == "orders.created" {
        orderEvents[event.orderId] = event;
        json data = event.data;
        json|error payloadJson = data.payload;
        if payloadJson is json {
            OrderPayload|error payload = payloadJson.cloneWithType(OrderPayload);
            if payload is OrderPayload {
                OrderLine[] lines = [];
                foreach OrderItemPayload item in payload.items {
                    lines.push({menuItemId: item.menuItemId, quantity: item.qty});
                }
                KitchenOrder kitchen = {
                    id: payload.orderId,
                    restaurantId: payload.restaurantId,
                    items: lines,
                    status: "PENDING_DECISION"
                };
                kitchenOrders[payload.orderId] = kitchen;
            } else {
                log:printError("restaurant order payload conversion failed", 'error = payload);
            }
        } else {
            log:printError("restaurant event payload extraction failed", 'error = payloadJson);
        }
    } else if event.eventType == "orders.cancelled" || event.eventType == "orders.autocancelled" {
        KitchenOrder? kitchen = kitchenOrders[event.orderId];
        if kitchen is KitchenOrder && kitchen.status != "READY" && kitchen.status != "CANCELLED" {
            kitchen.status = "CANCELLED";
            kitchenOrders[event.orderId] = kitchen;
        }
    } else if event.eventType == "orders.confirmed" {
        KitchenOrder? kitchen = kitchenOrders[event.orderId];
        if kitchen is KitchenOrder && kitchen.status == "ACCEPTED" {
            kitchen.paymentConfirmed = true;
            kitchenOrders[event.orderId] = kitchen;
        }
    }
    restaurantProcessedEvents[event.eventId] = true;
    log:printInfo("restaurant event processed: " + event.eventType + ":" + event.orderId);
    commitRestaurantRecord(consumer, kafkaRecord);
}

function publishRestaurantEvent(string eventType, RestaurantEvent eventSource, json payload) returns error? {
    kafka:Producer|error producer = ensureRestaurantProducer();
    if producer is error {
        return producer;
    }

    json|error summaryResult = eventSource.data.orderSummary;
    if summaryResult is error {
        return summaryResult;
    }
    json summary = summaryResult;
    json envelope = {
        eventId: uuid:createType4AsString(),
        eventType: eventType,
        occurredAt: time:utcToString(time:utcNow()),
        orderId: eventSource.orderId,
        correlationId: eventSource.correlationId,
        producerService: "restaurant-service",
        data: {orderSummary: summary, payload: payload}
    };
    string envelopeJson = envelope.toJsonString();
    check producer->send({topic: eventType, key: eventSource.orderId.toBytes(), value: envelopeJson.toBytes()});
    check producer->'flush();
}

function publishManualRestaurantEvent(string orderId, string eventType, json payload) returns error? {
    RestaurantEvent? sourceEvent = orderEvents[orderId];
    if sourceEvent is () {
        return error("orders.created event is not available");
    }
    return publishRestaurantEvent(eventType, sourceEvent, payload);
}

function ensureRestaurantProducer() returns kafka:Producer|error {
    kafka:Producer|error? current = restaurantProducer;
    if current is kafka:Producer {
        return current;
    }
    if current is error {
        return current;
    }
    kafka:Producer|error created = new (kafkaBootstrap, restaurantProducerConfiguration);
    restaurantProducer = created;
    return created;
}

function commitRestaurantRecord(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord) {
    kafka:PartitionOffset committed = {
        partition: kafkaRecord.offset.partition,
        offset: kafkaRecord.offset.offset + 1
    };
    kafka:Error? result = consumer->commitOffset([committed]);
    if result is kafka:Error {
        log:printError("restaurant Kafka offset commit failed", 'error = result);
    }
}
