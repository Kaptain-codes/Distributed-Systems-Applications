import ballerina/log;
import ballerina/uuid;
import ballerinax/kafka;

configurable boolean kafkaEnabled = false;
configurable string kafkaBootstrapServers = kafka:DEFAULT_URL;

const string PAYMENT_COMPLETED_TOPIC = "payments.completed";
const string PAYMENT_FAILED_TOPIC = "payments.failed";

type DomainEvent record {|
    readonly string eventId;
    string eventType;
    string aggregateId;
    string 'source;
    int schemaVersion;
    string occurredAt;
    json payload;
|};

type OrderCreatedPayload record {
    string orderId;
    string customerId;
    decimal totalAmount;
};

final kafka:Producer? paymentEventProducer = kafkaEnabled ? checkpanic new (kafkaBootstrapServers, {
        clientId: "payment-service-producer",
        acks: kafka:ACKS_ALL,
        retryCount: 5,
        enableIdempotence: true
    }) : ();

final kafka:Listener? orderCreatedListener = kafkaEnabled ? checkpanic new (kafkaBootstrapServers, {
        groupId: "payment-service-orders",
        clientId: "payment-service-consumer",
        topics: "orders.created",
        offsetReset: kafka:OFFSET_RESET_EARLIEST,
        autoCommit: false,
        pollingInterval: 1
    }) : ();

kafka:Service orderCreatedConsumer = service object {
    // Creates one deterministic pending payment for every new order.
    remote isolated function onConsumerRecord(kafka:Caller caller, DomainEvent[] events) {
        foreach DomainEvent domainEvent in events {
            error? result = handleOrderCreatedEvent(domainEvent);
            if result is error {
                log:printError("Order event could not create a payment",
                        eventId = domainEvent.eventId, 'error = result);
                return;
            }
        }
        kafka:Error? commitResult = caller->'commit();
        if commitResult is kafka:Error {
            log:printError("Payment consumer offset commit failed", 'error = commitResult);
        }
    }
};

function init() returns error? {
    kafka:Listener? eventListener = orderCreatedListener;
    if eventListener is kafka:Listener {
        check eventListener.attach(orderCreatedConsumer);
        check eventListener.'start();
    }
}

function stop() returns error? {
    kafka:Listener? eventListener = orderCreatedListener;
    if eventListener is kafka:Listener {
        check eventListener.gracefulStop();
    }
    kafka:Producer? eventProducer = paymentEventProducer;
    if eventProducer is kafka:Producer {
        check eventProducer->close();
    }
}

isolated function handleOrderCreatedEvent(DomainEvent domainEvent) returns error? {
    OrderCreatedPayload orderPayload = check domainEvent.payload.cloneWithType();
    string paymentId = string `payment-${orderPayload.orderId}`;
    Payment? existingPayment = check findPayment(paymentId);
    if existingPayment is Payment {
        return;
    }
    _ = check createPayment({
                                paymentId,
                                orderId: orderPayload.orderId,
                                customerId: orderPayload.customerId,
                                amount: orderPayload.totalAmount,
                                currency: "NAD",
                                requestedAt: domainEvent.occurredAt
                            });
}

isolated function publishPaymentDecisionEvent(Payment payment) returns error? {
    kafka:Producer? eventProducer = paymentEventProducer;
    if eventProducer is kafka:Producer {
        string topic = payment.status == COMPLETED ? PAYMENT_COMPLETED_TOPIC : PAYMENT_FAILED_TOPIC;
        string occurredAt = payment.processedAt ?: payment.requestedAt;
        DomainEvent domainEvent = {
            eventId: uuid:createType4AsString(),
            eventType: topic,
            aggregateId: payment.orderId,
            'source: "payment_service",
            schemaVersion: 1,
            occurredAt,
            payload: payment
        };
        check eventProducer->send({topic, key: payment.orderId.toBytes(), value: domainEvent});
    }
}
