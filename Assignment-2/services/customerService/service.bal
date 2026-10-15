import ballerina/http;
import ballerina/log;
import ballerina/uuid;

public type ErrorResponse record {|
    string 'error;
    string message;
|};

public type Customer record {|
    string id;
    string name;
    string email;
    string phone;
|};

public type CustomerInput record {|
    string name;
    string email;
    string phone;
|};

public type Address record {|
    string id;
    string customerId;
    string? label = ();
    string line1;
    string city;
    string country;
    string? region = ();
    boolean? is_default = ();
    string? postalCode = ();
|};

public type AddressInput record {|
    string? label = ();
    string line1;
    string city;
    string? country = ();
    string? region = ();
    boolean? is_default = ();
    string? postalCode = ();
|};

map<Customer> customers = {};
map<Address[]> customerAddresses = {};

function failure(string code, string message, int status) returns http:Response {
    http:Response response = new;
    response.statusCode = status;
    response.setJsonPayload(<ErrorResponse>{'error: code, message: message});
    return response;
}

function validText(string value) returns boolean {
    return value.trim().length() > 0;
}

service /customer on new http:Listener(9090) {
    function init() returns error? {
        check initCustomerRepository();
    }

    resource function get health() returns json {
        return {status: "UP", 'service: "customer"};
    }

    resource function post customers(@http:Payload CustomerInput input) returns Customer|http:Response {
        if !validText(input.name) || !validText(input.email) || !input.email.includes("@") {
            return failure("VALIDATION_ERROR", "name and a valid email are required", 400);
        }
        string id = uuid:createType4AsString();
        Customer customer = {id, name: input.name.trim(), email: input.email.trim().toLowerAscii(),
            phone: input.phone.trim()};
        error? saved = customerRepository.saveCustomer(customer);
        if saved is error {
            log:printError("customer database save failed", 'error = saved);
            return failure("DATABASE_ERROR", "customer could not be saved", 503);
        }
        return customer;
    }

    resource function get customers/[string id]() returns Customer|http:Response {
        Customer|error? result = customerRepository.getCustomer(id);
        if result is error {
            log:printError("customer database lookup failed", 'error = result);
            return failure("DATABASE_ERROR", "customer lookup failed", 503);
        }
        Customer? customer = result;
        if customer is () {
            return failure("NOT_FOUND", "customer not found", 404);
        }
        return customer;
    }

    resource function put customers/[string id](@http:Payload CustomerInput input)
            returns Customer|http:Response {
        if !validText(input.name) || !validText(input.email) || !input.email.includes("@") {
            return failure("VALIDATION_ERROR", "name and a valid email are required", 400);
        }
        Customer|error? currentResult = customerRepository.getCustomer(id);
        if currentResult is error {
            log:printError("customer database lookup failed", 'error = currentResult);
            return failure("DATABASE_ERROR", "customer lookup failed", 503);
        }
        Customer? current = currentResult;
        if current is () {
            return failure("NOT_FOUND", "customer not found", 404);
        }
        Customer updated = {id, name: input.name.trim(), email: input.email.trim().toLowerAscii(),
            phone: input.phone.trim()};
        error? saved = customerRepository.saveCustomer(updated);
        if saved is error {
            log:printError("customer database save failed", 'error = saved);
            return failure("DATABASE_ERROR", "customer could not be saved", 503);
        }
        return updated;
    }

    resource function post customers/[string id]/addresses(@http:Payload AddressInput input)
            returns Address|http:Response {
        Customer|error? customerResult = customerRepository.getCustomer(id);
        if customerResult is error {
            log:printError("customer database lookup failed", 'error = customerResult);
            return failure("DATABASE_ERROR", "customer lookup failed", 503);
        }
        Customer? customer = customerResult;
        if customer is () {
            return failure("NOT_FOUND", "customer not found", 404);
        }
        string country = input.country ?: input.region ?: "";
        if !validText(input.line1) || !validText(input.city) || !validText(country) {
            return failure("VALIDATION_ERROR", "address fields are required", 400);
        }
        string addressId = uuid:createType4AsString();
        Address address = {id: addressId, customerId: id, line1: input.line1.trim(),
            label: input.label ?: "Home", city: input.city.trim(), country: "Namibia",
            region: input.region ?: country.trim(), is_default: input.is_default,
            postalCode: input.postalCode};
        error? saved = customerRepository.saveAddress(address);
        if saved is error {
            log:printError("customer address save failed", 'error = saved);
            return failure("DATABASE_ERROR", "address could not be saved", 503);
        }
        return address;
    }

    resource function get customers/[string id]/addresses() returns Address[]|http:Response {
        Customer|error? customerResult = customerRepository.getCustomer(id);
        if customerResult is error {
            log:printError("customer database lookup failed", 'error = customerResult);
            return failure("DATABASE_ERROR", "customer lookup failed", 503);
        }
        Customer? customer = customerResult;
        if customer is () {
            return failure("NOT_FOUND", "customer not found", 404);
        }
        Address[]|error addresses = customerRepository.listAddresses(id);
        if addresses is error {
            log:printError("customer address lookup failed", 'error = addresses);
            return failure("DATABASE_ERROR", "addresses could not be loaded", 503);
        }
        return addresses;
    }

    resource function get customers/[string id]/orders() returns json|http:Response {
        Customer|error? customerResult = customerRepository.getCustomer(id);
        if customerResult is error {
            log:printError("customer database lookup failed", 'error = customerResult);
            return failure("DATABASE_ERROR", "customer lookup failed", 503);
        }
        Customer? customer = customerResult;
        if customer is () {
            return failure("NOT_FOUND", "customer not found", 404);
        }
        return [];
    }

    resource function get internal/customers/[string customerId]/addresses/[string addressId]/validate()
            returns json|http:Response {
        Customer|error? customerResult = customerRepository.getCustomer(customerId);
        if customerResult is error {
            log:printError("customer database lookup failed", 'error = customerResult);
            return failure("DATABASE_ERROR", "customer lookup failed", 503);
        }
        Customer? customer = customerResult;
        if customer is () {
            return {valid: false, customerId, addressId, deliveryAddress: ()};
        }
        Address[]|error addressResult = customerRepository.listAddresses(customerId);
        if addressResult is error {
            log:printError("customer address lookup failed", 'error = addressResult);
            return failure("DATABASE_ERROR", "addresses could not be loaded", 503);
        }
        Address[] list = addressResult;
        foreach Address address in list {
            if address.id == addressId {
                return {valid: true, customerId, addressId, deliveryAddress: address};
            }
        }
        return {valid: false, customerId, addressId, deliveryAddress: ()};
    }
}
