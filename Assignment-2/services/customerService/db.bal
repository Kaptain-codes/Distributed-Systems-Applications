import ballerina/sql;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;

configurable boolean durableStateEnabled = false;
configurable string mysqlHost = "localhost";
configurable int mysqlPort = 3306;
configurable string mysqlDatabase = "customer";
configurable string mysqlUser = "customer_app";
configurable string mysqlPassword = "";

mysql:Client|sql:Error customerDb = error("customer database is not initialized");

type CustomerRepository object {
    public function saveCustomer(Customer customer) returns error?;
    public function getCustomer(string id) returns Customer|error?;
    public function saveAddress(Address address) returns error?;
    public function listAddresses(string customerId) returns Address[]|error;
};

type CustomerRow record {|
    string id;
    string name;
    string email;
    string phone;
|};

type AddressRow record {|
    string id;
    string customerId;
    string label;
    string line1;
    string city;
    string region;
    boolean isDefault;
|};

class InMemoryCustomerRepository {
    *CustomerRepository;

    public function saveCustomer(Customer customer) returns error? {
        customers[customer.id] = customer;
    }

    public function getCustomer(string id) returns Customer? {
        return customers[id];
    }

    public function saveAddress(Address address) returns error? {
        Address[] existing = customerAddresses[address.customerId] ?: [];
        existing.push(address);
        customerAddresses[address.customerId] = existing;
    }

    public function listAddresses(string customerId) returns Address[] {
        return customerAddresses[customerId] ?: [];
    }
}

class MySqlCustomerRepository {
    *CustomerRepository;

    public function saveCustomer(Customer customer) returns error? {
        return saveCustomerToMySql(customer);
    }

    public function getCustomer(string id) returns Customer|error? {
        return getCustomerFromMySql(id);
    }

    public function saveAddress(Address address) returns error? {
        return saveAddressToMySql(address);
    }

    public function listAddresses(string customerId) returns Address[]|error {
        return listAddressesFromMySql(customerId);
    }
}

CustomerRepository customerRepository = new InMemoryCustomerRepository();

function initCustomerRepository() returns error? {
    if !durableStateEnabled {
        return;
    }
    customerDb = check new (
        host = mysqlHost,
        user = mysqlUser,
        password = mysqlPassword,
        database = mysqlDatabase,
        port = mysqlPort,
        connectionPool = {maxOpenConnections: 10}
    );
    customerRepository = new MySqlCustomerRepository();
}

function saveCustomerToMySql(Customer customer) returns error? {
    mysql:Client db = check customerDb;
    _ = check db->execute(
        `INSERT INTO customers (id, name, email, phone)
         VALUES (${customer.id}, ${customer.name}, ${customer.email}, ${customer.phone})
         ON DUPLICATE KEY UPDATE name = VALUES(name), email = VALUES(email),
            phone = VALUES(phone)`
    );
}

function getCustomerFromMySql(string id) returns Customer|error? {
    mysql:Client db = check customerDb;
    stream<CustomerRow, sql:Error?> rows = db->query(
        `SELECT id, name, email, phone FROM customers WHERE id = ${id}`
    );
    record {| CustomerRow value; |}|error? next = rows.next();
    if next is error || next is () {
        return next is error ? next : ();
    }
    return {id: next.value.id, name: next.value.name, email: next.value.email,
        phone: next.value.phone};
}

function saveAddressToMySql(Address address) returns error? {
    mysql:Client db = check customerDb;
    string label = address.label ?: "Home";
    string region = address.region ?: address.country;
    boolean isDefault = address.is_default ?: false;
    _ = check db->execute(
        `INSERT INTO addresses (id, customer_id, label, line1, city, region, is_default)
         VALUES (${address.id}, ${address.customerId}, ${label}, ${address.line1},
            ${address.city}, ${region}, ${isDefault})`
    );
}

function listAddressesFromMySql(string customerId) returns Address[]|error {
    mysql:Client db = check customerDb;
    stream<AddressRow, sql:Error?> rows = db->query(
        `SELECT id, customer_id AS customerId, label, line1, city, region,
            is_default AS isDefault FROM addresses WHERE customer_id = ${customerId}`
    );
    Address[] result = [];
    while true {
        record {| AddressRow value; |}|error? next = rows.next();
        if next is error {
            return next;
        }
        if next is () {
            break;
        }
        AddressRow row = next.value;
        result.push({
            id: row.id,
            customerId: row.customerId,
            label: row.label,
            line1: row.line1,
            city: row.city,
            country: "Namibia",
            region: row.region,
            is_default: row.isDefault
        });
    }
    return result;
}
