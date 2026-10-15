import ballerina/log;
import ballerina/uuid;
import ballerinax/kafka;

configurable boolean kafkaEnabled = false;
configurable string kafkaBootstrapServers = kafka:DEFAULT_URL;

const string ORDER_CREATED_TOPIC = "orders.created";
const string ORDER_CONFIRMED_TOPIC = "orders.confirmed";
const string ORDER_PREPARING_TOPIC = "orders.preparing";
const string ORDER_READY_TOPIC = "orders.ready";
const string ORDER_OUT_FOR_DELIVERY_TOPIC = "orders.out_for_delivery";
const string ORDER_DELIVERED_TOPIC = "orders.delivered";
const string ORDER_CANCELLED_TOPIC = "orders.cancelled";

type DomainEvent record {|
    readonly string eventId;
    string eventType;
    string aggregateId;
    string 'source;
    int schemaVersion;
    string occurredAt;
    json payload;
|};

final kafka:Producer? orderEventProducer = kafkaEnabled ? checkpanic new (kafkaBootstrapServers, {
        clientId: "order-service-producer",
        acks: kafka:ACKS_ALL,
        retryCount: 5,
        enableIdempotence: true
    }) : ();

final kafka:Listener? orderWorkflowListener = kafkaEnabled ? checkpanic new (kafkaBootstrapServers, {
        groupId: "order-service-workflow",
        clientId: "order-service-consumer",
        topics: ["payments.completed", "delivery.assigned", "delivery.completed"],
        offsetReset: kafka:OFFSET_RESET_EARLIEST,
        autoCommit: false,
        pollingInterval: 1
    }) : ();

kafka:Service orderWorkflowConsumer = service object {
    // Applies only transitions owned by the Order Service, then commits the batch.
    remote isolated function onConsumerRecord(kafka:Caller caller, DomainEvent[] events) {
        foreach DomainEvent domainEvent in events {
            error? result = applyWorkflowEvent(domainEvent);
            if result is error {
                log:printError("Order workflow event processing failed",
                        eventId = domainEvent.eventId, eventType = domainEvent.eventType, 'error = result);
                return;
            }
        }
        kafka:Error? commitResult = caller->'commit();
        if commitResult is kafka:Error {
            log:printError("Order workflow offset commit failed", 'error = commitResult);
        }
    }
};

function init() returns error? {
    kafka:Listener? workflowListener = orderWorkflowListener;
    if workflowListener is kafka:Listener {
        check workflowListener.attach(orderWorkflowConsumer);
        check workflowListener.'start();
    }
}

function stop() returns error? {
    kafka:Listener? workflowListener = orderWorkflowListener;
    if workflowListener is kafka:Listener {
        check workflowListener.gracefulStop();
    }
    kafka:Producer? eventProducer = orderEventProducer;
    if eventProducer is kafka:Producer {
        check eventProducer->close();
    }
}

isolated function publishOrderCreatedEvent(FoodOrder foodOrder) returns error? {
    check publishOrderEvent(ORDER_CREATED_TOPIC, foodOrder, foodOrder.createdAt);
}

isolated function publishOrderStatusEvent(FoodOrder foodOrder) returns error? {
    check publishOrderEvent(topicForOrderStatus(foodOrder.status), foodOrder, foodOrder.updatedAt);
}

isolated function publishOrderEvent(string topic, FoodOrder foodOrder, string occurredAt) returns error? {
    kafka:Producer? eventProducer = orderEventProducer;
    if eventProducer is kafka:Producer {
        DomainEvent domainEvent = {
            eventId: uuid:createType4AsString(),
            eventType: topic,
            aggregateId: foodOrder.orderId,
            'source: "order_service",
            schemaVersion: 1,
            occurredAt,
            payload: foodOrder
        };
        check eventProducer->send({topic, key: foodOrder.orderId.toBytes(), value: domainEvent});
    }
}

isolated function topicForOrderStatus(OrderStatus status) returns string {
    match status {
        CONFIRMED => {
            return ORDER_CONFIRMED_TOPIC;
        }
        PREPARING => {
            return ORDER_PREPARING_TOPIC;
        }
        READY => {
            return ORDER_READY_TOPIC;
        }
        OUT_FOR_DELIVERY => {
            return ORDER_OUT_FOR_DELIVERY_TOPIC;
        }
        DELIVERED => {
            return ORDER_DELIVERED_TOPIC;
        }
        CANCELLED => {
            return ORDER_CANCELLED_TOPIC;
        }
        _ => {
            return ORDER_CREATED_TOPIC;
        }
    }
}

isolated function applyWorkflowEvent(DomainEvent domainEvent) returns error? {
    OrderStatus? requestedStatus = ();
    match domainEvent.eventType {
        "payments.completed" => {
            requestedStatus = CONFIRMED;
        }
        "delivery.assigned" => {
            requestedStatus = OUT_FOR_DELIVERY;
        }
        "delivery.completed" => {
            requestedStatus = DELIVERED;
        }
    }
    if requestedStatus is () {
        return;
    }

    FoodOrder? foodOrder = check findOrder(domainEvent.aggregateId);
    if foodOrder is () {
        return error(string `Order '${domainEvent.aggregateId}' referenced by event was not found`);
    }
    if foodOrder.status == requestedStatus || orderStatusHasPassed(foodOrder.status, requestedStatus) {
        return;
    }

    FoodOrder transitionedOrder = check transitionOrder(foodOrder.orderId, {
                                                                               status: requestedStatus,
                                                                               occurredAt: domainEvent.occurredAt
                                                                           });
    check publishOrderStatusEvent(transitionedOrder);
}

isolated function orderStatusHasPassed(OrderStatus currentStatus, OrderStatus requestedStatus) returns boolean {
    int currentPosition = orderStatusPosition(currentStatus);
    int requestedPosition = orderStatusPosition(requestedStatus);
    return currentPosition >= 0 && requestedPosition >= 0 && currentPosition > requestedPosition;
}

isolated function orderStatusPosition(OrderStatus status) returns int {
    match status {
        CREATED => {
            return 0;
        }
        CONFIRMED => {
            return 1;
        }
        PREPARING => {
            return 2;
        }
        READY => {
            return 3;
        }
        OUT_FOR_DELIVERY => {
            return 4;
        }
        DELIVERED => {
            return 5;
        }
        CANCELLED => {
            return -1;
        }
    }
    return -1;
}
