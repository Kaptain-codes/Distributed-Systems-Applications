import ballerina/os;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;

function envOr(string key, string fallback) returns string {
    string val = os:getEnv(key);
    return val == "" ? fallback : val;
}

final string DB_HOST = envOr("CUSTOMER_DB_HOST", "customer-db");
final int DB_PORT = checkpanic int:fromString(envOr("CUSTOMER_DB_PORT", "3306"));
final string DB_USER = envOr("CUSTOMER_DB_USER", "customer_app");
final string DB_PASSWORD = envOr("CUSTOMER_DB_PASSWORD", "");
final string DB_NAME = envOr("CUSTOMER_DB_NAME", "customer");

final mysql:Client customerDb = check new(
    host = DB_HOST,
    port = DB_PORT,
    user = DB_USER,
    password = DB_PASSWORD,
    database = DB_NAME
);

public type Customer record {|
    string id;
    string name;
    string email;
    string? phone;
|};

public type NewCustomer record {|
    string name;
    string email;
    string? phone;
|};

public isolated function customerExists(string customerId) returns boolean|error {
    int count = check customerDb->queryRow(`
        SELECT COUNT(*) AS cnt FROM customers WHERE id = ${customerId}
    `);
    return count > 0;
}