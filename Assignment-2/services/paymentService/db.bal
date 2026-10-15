import ballerina/log;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;
import ballerinax/redis;
import ballerina/sql;

configurable boolean durableStateEnabled = false;
configurable string mysqlHost = "localhost";
configurable int mysqlPort = 3306;
configurable string mysqlDatabase = "payment";
configurable string mysqlUser = "payment_app";
configurable string mysqlPassword = "";
configurable string redisHost = "payment-redis";
configurable int redisPort = 6379;

mysql:Client|sql:Error paymentDb = error("payment database is not initialized");
redis:Client? paymentRedisClient = ();

function initializePaymentRedisClient() {
    if paymentRedisClient is redis:Client {
        return;
    }
    redis:Client|error result = new (connection = {host: redisHost, port: redisPort});
    if result is redis:Client {
        paymentRedisClient = result;
        return;
    }
    log:printWarn("Payment Redis is unavailable; continuing without Redis", 'error = result);
}

type PaymentRepository object {
    public function save(Payment payment, string? customerId = ()) returns error?;
    public function getById(string paymentId) returns Payment|error?;
    public function getByOrderId(string orderId) returns Payment|error?;
};

type PaymentRow record {|
    string paymentId;
    string orderId;
    decimal amount;
    string currency;
    string method;
    string status;
    string createdAt;
    string updatedAt;
|};

class InMemoryPaymentRepository {
    *PaymentRepository;

    private map<Payment> records = {};

    public function save(Payment payment, string? customerId = ()) returns error? {
        self.records[payment.paymentId] = payment;
    }

    public function getById(string paymentId) returns Payment|error? {
        return self.records[paymentId];
    }

    public function getByOrderId(string orderId) returns Payment|error? {
        foreach Payment payment in self.records {
            if payment.orderId == orderId {
                return payment;
            }
        }
        return ();
    }
}

class MySqlPaymentRepository {
    *PaymentRepository;

    public function save(Payment payment, string? customerId = ()) returns error? {
        return savePaymentToMySql(payment, customerId);
    }

    public function getById(string paymentId) returns Payment|error? {
        return getPaymentByIdFromMySql(paymentId);
    }

    public function getByOrderId(string orderId) returns Payment|error? {
        return getPaymentByOrderIdFromMySql(orderId);
    }
}

PaymentRepository paymentRepository = new InMemoryPaymentRepository();

function initPaymentRepository() returns error? {
    if !durableStateEnabled {
        return;
    }
    paymentDb = check new (
        host = mysqlHost,
        user = mysqlUser,
        password = mysqlPassword,
        database = mysqlDatabase,
        port = mysqlPort,
        connectionPool = {maxOpenConnections: 10}
    );
    paymentRepository = new MySqlPaymentRepository();
}

function savePaymentToMySql(Payment payment, string? customerId) returns error? {
    mysql:Client db = check paymentDb;
    string newCustomerId = customerId ?: "";
    _ = check db->execute(
        `INSERT INTO payments (id, order_id, customer_id, amount, currency, method, status,
            created_at, updated_at)
         VALUES (${payment.paymentId}, ${payment.orderId}, ${newCustomerId}, ${payment.amount},
            ${payment.currency}, ${payment.method}, ${payment.status}, CURRENT_TIMESTAMP(6),
            CURRENT_TIMESTAMP(6))
         ON DUPLICATE KEY UPDATE customer_id = IF(${customerId} IS NULL, customer_id,
            VALUES(customer_id)), amount = VALUES(amount), currency = VALUES(currency),
            method = VALUES(method), status = VALUES(status),
            updated_at = CURRENT_TIMESTAMP(6)`
    );
}

function getPaymentByIdFromMySql(string paymentId) returns Payment|error? {
    mysql:Client db = check paymentDb;
    stream<PaymentRow, sql:Error?> rows = db->query(
        `SELECT id AS paymentId, order_id AS orderId, amount, currency, method, status,
            DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%s.%fZ') AS createdAt,
            DATE_FORMAT(updated_at, '%Y-%m-%dT%H:%i:%s.%fZ') AS updatedAt
         FROM payments WHERE id = ${paymentId}`
    );
    record {| PaymentRow value; |}|error? next = rows.next();
    if next is error || next is () {
        return next is error ? next : ();
    }
    return paymentFromRow(next.value);
}

function getPaymentByOrderIdFromMySql(string orderId) returns Payment|error? {
    mysql:Client db = check paymentDb;
    stream<PaymentRow, sql:Error?> rows = db->query(
        `SELECT id AS paymentId, order_id AS orderId, amount, currency, method, status,
            DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%s.%fZ') AS createdAt,
            DATE_FORMAT(updated_at, '%Y-%m-%dT%H:%i:%s.%fZ') AS updatedAt
         FROM payments WHERE order_id = ${orderId}`
    );
    record {| PaymentRow value; |}|error? next = rows.next();
    if next is error || next is () {
        return next is error ? next : ();
    }
    return paymentFromRow(next.value);
}

function paymentFromRow(PaymentRow row) returns Payment {
    return {
        paymentId: row.paymentId,
        orderId: row.orderId,
        amount: row.amount,
        currency: row.currency,
        method: row.method,
        status: row.status,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt
    };
}
