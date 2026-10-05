import ballerinax/kafka;
import ballerina/lang.'string as str;
import ballerina/log;
import ballerina/task;

configurable boolean kafkaRuntimeEnabled = false;
configurable string kafkaBootstrap = "kafka:9092";

type NotificationEvent record {|
    string eventId;
    string eventType;
    string orderId;
    string correlationId;
    json occurredAt = ();
    string producerService = "";
    json data = {};
|};

final kafka:ConsumerConfiguration notificationConsumerConfiguration = {
    groupId: "notification-service",
    topics: ["orders.created", "orders.confirmed", "orders.preparing", "orders.ready",
        "orders.out_for_delivery", "orders.delivered", "orders.cancelled", "orders.autocancelled"],
    offsetReset: "earliest",
    autoCommit: false,
    pollingInterval: 1,
    maxPollRecords: 10
};

kafka:Consumer|error? notificationConsumer = ();
map<boolean> notificationProcessedEvents = {};

function startNotificationKafkaRuntime() returns error? {
    if !kafkaRuntimeEnabled {
        return;
    }
    kafka:Consumer|error consumer = new (kafkaBootstrap, notificationConsumerConfiguration);
    if consumer is error {
        return consumer;
    }
    notificationConsumer = consumer;
    _ = check task:scheduleJobRecurByFrequency(new NotificationKafkaJob(), 1);
}

class NotificationKafkaJob {
    *task:Job;

    public function execute() {
        kafka:Consumer|error? current = notificationConsumer;
        if current is kafka:Consumer {
            kafka:AnydataConsumerRecord[]|kafka:Error records = current->poll(1);
            if records is kafka:Error {
                log:printError("notification Kafka poll failed", 'error = records);
                return;
            }
            foreach kafka:AnydataConsumerRecord kafkaRecord in records {
                handleNotificationRecord(current, kafkaRecord);
            }
        }
    }
}

function handleNotificationRecord(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord) {
    if kafkaRecord.value !is byte[] {
        commitNotificationRecord(consumer, kafkaRecord);
        return;
    }
    string|error raw = str:fromBytes(<byte[]>kafkaRecord.value);
    if raw is error {
        commitNotificationRecord(consumer, kafkaRecord);
        return;
    }
    json|error parsed = raw.fromJsonString();
    if parsed is error {
        commitNotificationRecord(consumer, kafkaRecord);
        return;
    }
    NotificationEvent|error event = parsed.cloneWithType(NotificationEvent);
    if event is error || notificationProcessedEvents[event.eventId] == true {
        commitNotificationRecord(consumer, kafkaRecord);
        return;
    }
    string customerId = "";
    string restaurantId = "";
    json|error summary = event.data.orderSummary;
    if summary is map<json> {
        json? customer = summary["customerId"];
        json? restaurant = summary["restaurantId"];
        if customer is string {
            customerId = customer;
        }
        if restaurant is string {
            restaurantId = restaurant;
        }
    }
    if customerId.length() > 0 {
        _ = addNotification("CUSTOMER", customerId, event.orderId, event.eventId,
            "Order status changed to " + event.eventType);
    }
    if restaurantId.length() > 0 && event.eventType == "orders.created" {
        _ = addNotification("RESTAURANT", restaurantId, event.orderId, event.eventId,
            "New order received");
    }
    notificationProcessedEvents[event.eventId] = true;
    commitNotificationRecord(consumer, kafkaRecord);
}

function commitNotificationRecord(kafka:Consumer consumer, kafka:AnydataConsumerRecord kafkaRecord) {
    kafka:PartitionOffset committed = {
        partition: kafkaRecord.offset.partition,
        offset: kafkaRecord.offset.offset + 1
    };
    kafka:Error? result = consumer->commitOffset([committed]);
    if result is kafka:Error {
        log:printError("notification Kafka offset commit failed", 'error = result);
    }
}
