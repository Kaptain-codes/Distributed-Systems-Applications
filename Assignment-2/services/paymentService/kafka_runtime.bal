import ballerinax/kafka;
import ballerina/lang.'string as str;
import ballerina/log;
import ballerina/task;
import ballerina/time;
import ballerina/uuid;

configurable boolean kafkaRuntimeEnabled = false;
configurable string kafkaBootstrap = "kafka:9092";

type PaymentEvent record {|
    string eventId;
    string eventType;
    string orderId;
    string correlationId;
    json occurredAt = ();
    string producerService = "";
    json data = {};
|};

type PaymentPayload record {|
    json orderSummary = {};
    json payload = {};
|};

final kafka:ConsumerConfiguration paymentConsumerConfiguration = {
    groupId: "payment-service",
    topics: ["payment.requested", "orders.cancelled", "orders.autocancelled"],
    offsetReset: "earliest",
    autoCommit: false,
    pollingInterval: 1,
    maxPollRecords: 10
};

final kafka:ProducerConfiguration paymentProducerConfiguration = {
    clientId: "payment-service",
    acks: "all",
    retryCount: 3
};

kafka:Consumer|error? paymentConsumer = ();
kafka:Producer|error? paymentProducer = ();
map<boolean> paymentProcessedEvents = {};

function startPaymentKafkaRuntime() returns error? {
    if !kafkaRuntimeEnabled {
        return;
    }
    kafka:Consumer|error consumer = new (kafkaBootstrap, paymentConsumerConfiguration);
    if consumer is error {
        return consumer;
    }
    paymentConsumer = consumer;
    _ = check task:scheduleJobRecurByFrequency(new PaymentKafkaJob(), 1);
}

class PaymentKafkaJob {
    *task:Job;

    public function execute() {
        kafka:Consumer|error? current = paymentConsumer;
        if current is kafka:Consumer {
            kafka:AnydataConsumerRecord[]|kafka:Error records = current->poll(1);
            if records is kafka:Error {
                log:printError("payment Kafka poll failed", 'error = records);
                return;
            }
            foreach kafka:AnydataConsumerRecord kafkaRecord in records {
                handlePaymentRecord(current, kafkaRecord);
            }
        }
    }
}

function handlePaymentRecord(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord) {
    if kafkaRecord.value !is byte[] {
        commitPaymentRecord(consumer, kafkaRecord);
        return;
    }
    string|error raw = str:fromBytes(<byte[]>kafkaRecord.value);
    if raw is error {
        commitPaymentRecord(consumer, kafkaRecord);
        return;
    }
    json|error parsed = raw.fromJsonString();
    if parsed is error {
        commitPaymentRecord(consumer, kafkaRecord);
        return;
    }
    PaymentEvent|error event = parsed.cloneWithType(PaymentEvent);
    if event is error || paymentProcessedEvents[event.eventId] == true {
        commitPaymentRecord(consumer, kafkaRecord);
        return;
    }
    if event.eventType == "payment.requested" {
        PaymentPayload|error request = event.data.cloneWithType(PaymentPayload);
        if request is PaymentPayload {
            json summary = request.orderSummary;
            decimal amount = 0;
            if summary is map<json> {
                json? total = summary["total"];
                if total is decimal {
                    amount = total;
                } else if total is int {
                    amount = <decimal>total;
                }
            }
            string method = "CARD";
            if request.payload is map<json> {
                map<json> requestedPayload = <map<json>>request.payload;
                json? requestedMethod = requestedPayload["paymentMethod"];
                if requestedMethod is string {
                    method = requestedMethod;
                }
            }
            string now = time:utcToString(time:utcNow());
            Payment payment = {
                paymentId: uuid:createType4AsString(), orderId: event.orderId,
                amount: amount, method: method, createdAt: now, updatedAt: now
            };
            payment.status = method == "SIM_DECLINE" ? "FAILED" : "COMPLETED";
            payments[payment.paymentId] = payment;
            string resultTopic = payment.status == "COMPLETED" ? "payments.completed" : "payments.failed";
            error? published = publishPaymentEvent(resultTopic, event, payment);
            if published is error {
                log:printError("payment event publication failed", 'error = published);
                return;
            }
        }
    } else if event.eventType == "orders.cancelled" || event.eventType == "orders.autocancelled" {
        foreach string paymentId in payments.keys() {
            Payment? payment = payments[paymentId];
            if payment is Payment && payment.orderId == event.orderId &&
                payment.status == "COMPLETED" {
                payment.status = "REFUNDED";
                payments[paymentId] = payment;
                error? published = publishPaymentEvent("payments.refunded", event, payment);
                if published is error {
                    log:printError("payment refund publication failed", 'error = published);
                    return;
                }
            }
        }
    }
    paymentProcessedEvents[event.eventId] = true;
    commitPaymentRecord(consumer, kafkaRecord);
}

function publishPaymentEvent(string topic, PaymentEvent sourceEvent, Payment payment) returns error? {
    kafka:Producer|error producer = ensurePaymentProducer();
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
        producerService: "payment-service",
        data: {orderSummary: summary, payload: payment}
    };
    string raw = envelope.toJsonString();
    check producer->send({topic: topic, key: sourceEvent.orderId.toBytes(), value: raw.toBytes()});
    check producer->'flush();
}

function ensurePaymentProducer() returns kafka:Producer|error {
    kafka:Producer|error? current = paymentProducer;
    if current is kafka:Producer {
        return current;
    }
    if current is error {
        return current;
    }
    kafka:Producer|error created = new (kafkaBootstrap, paymentProducerConfiguration);
    paymentProducer = created;
    return created;
}

function commitPaymentRecord(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord) {
    kafka:PartitionOffset committed = {
        partition: kafkaRecord.offset.partition,
        offset: kafkaRecord.offset.offset + 1
    };
    kafka:Error? result = consumer->commitOffset([committed]);
    if result is kafka:Error {
        log:printError("payment Kafka offset commit failed", 'error = result);
    }
}
