import ballerina/http;
import ballerina/os;
import ballerinax/kafka;
import ballerinax/mongodb;

function envOr(string key, string fallback) returns string {
    string val = os:getEnv(key);
    return val == "" ? fallback : val;
}

final string MONGO_HOST = envOr("ORDER_DB_HOST", "order-db");
final int MONGO_PORT = checkpanic int:fromString(envOr("ORDER_DB_PORT", "27017"));
final string MONGO_USER = envOr("ORDER_DB_USER", "order_app");
final string MONGO_PASSWORD = envOr("ORDER_DB_PASSWORD", "");
final string MONGO_DB_NAME = envOr("ORDER_DB_NAME", "orders");

final string KAFKA_BOOTSTRAP_SERVERS = envOr("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092");

final string CUSTOMER_SERVICE_URL = envOr("CUSTOMER_SERVICE_URL", "http://customer-service:9090");
final http:Client customerClient = check new (CUSTOMER_SERVICE_URL);

final string MONGO_URI = string `mongodb://${MONGO_USER}:${MONGO_PASSWORD}@${MONGO_HOST}:${MONGO_PORT}/?authSource=${MONGO_DB_NAME}`;

final mongodb:Client orderMongo = check new ({
    connection: MONGO_URI
});

isolated function initOrderDb() returns mongodb:Database|error {
    return orderMongo->getDatabase(MONGO_DB_NAME);
}
final mongodb:Database orderDb = check initOrderDb();

isolated function initOrderCollection() returns mongodb:Collection|error {
    return orderDb->getCollection("orders");
}
final mongodb:Collection orderCollection = check initOrderCollection();

final kafka:Producer orderProducer = check new (KAFKA_BOOTSTRAP_SERVERS, {
    clientId: "order-service-producer",
    acks: "all",
    retryCount: 3
});

public type OrderStatus "CREATED"|"CONFIRMED"|"PREPARING"|"READY"
                        |"OUT_FOR_DELIVERY"|"DELIVERED"|"CANCELLED";

public type OrderItem record {|
    string menuItemId;
    string name;
    int quantity;
    decimal price;
|};

public type CreateOrderRequest record {|
    string customerId;
    string restaurantId;
    OrderItem[] items;
|};

public type UpdateOrderStatusRequest record {|
    OrderStatus status;
|};

public type Order record {|
     string id;
    string customerId;
    string restaurantId;
    OrderItem[] items;
    decimal total;
    OrderStatus status;
    string createdAt;
    string updatedAt;
|};

function isValidTransition(OrderStatus current, OrderStatus next) returns boolean {
    match current {
        "CREATED" => { return next == "CONFIRMED" || next == "CANCELLED"; }
        "CONFIRMED" => { return next == "PREPARING" || next == "CANCELLED"; }
        "PREPARING" => { return next == "READY" || next == "CANCELLED"; }
        "READY" => { return next == "OUT_FOR_DELIVERY"; }
        "OUT_FOR_DELIVERY" => { return next == "DELIVERED"; }
        _ => { return false; }
    }
}

function statusToTopic(OrderStatus status) returns string {
    string lower = status.toLowerAscii();
    return "orders." + lower;
}

function publishStatusEvent(Order ord) returns error? {
    string topic = statusToTopic(ord.status);
    check orderProducer->send({
        topic: topic,
        value: ord.toJsonString().toBytes()
    });
}

function customerExists(string customerId) returns boolean|error {
    http:Response res = check customerClient->get(string `/customer/${customerId}`);
    return res.statusCode == 200;
}