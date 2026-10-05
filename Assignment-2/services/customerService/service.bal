import ballerina/http;

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
    string line1;
    string city;
    string country;
    string? postalCode = ();
|};

public type AddressInput record {|
    string line1;
    string city;
    string country;
    string? postalCode = ();
|};

map<Customer> customers = {};
map<Address[]> customerAddresses = {};
int nextCustomerId = 1;
int nextAddressId = 1;

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
    resource function get health() returns json {
        return {status: "UP", 'service: "customer"};
    }

    resource function post customers(@http:Payload CustomerInput input) returns Customer|http:Response {
        if !validText(input.name) || !validText(input.email) || !input.email.includes("@") {
            return failure("VALIDATION_ERROR", "name and a valid email are required", 400);
        }
        string id = "cus-" + nextCustomerId.toString();
        nextCustomerId += 1;
        Customer customer = {id, name: input.name.trim(), email: input.email.trim().toLowerAscii(),
            phone: input.phone.trim()};
        customers[id] = customer;
        return customer;
    }

    resource function get customers/[string id]() returns Customer|http:Response {
        Customer? customer = customers[id];
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
        if !customers.hasKey(id) {
            return failure("NOT_FOUND", "customer not found", 404);
        }
        Customer updated = {id, name: input.name.trim(), email: input.email.trim().toLowerAscii(),
            phone: input.phone.trim()};
        customers[id] = updated;
        return updated;
    }

    resource function post customers/[string id]/addresses(@http:Payload AddressInput input)
            returns Address|http:Response {
        if !customers.hasKey(id) {
            return failure("NOT_FOUND", "customer not found", 404);
        }
        if !validText(input.line1) || !validText(input.city) || !validText(input.country) {
            return failure("VALIDATION_ERROR", "address fields are required", 400);
        }
        string addressId = "addr-" + nextAddressId.toString();
        nextAddressId += 1;
        Address address = {id: addressId, customerId: id, line1: input.line1.trim(),
            city: input.city.trim(), country: input.country.trim(), postalCode: input.postalCode};
        Address[] existing = customerAddresses[id] ?: [];
        existing.push(address);
        customerAddresses[id] = existing;
        return address;
    }

    resource function get customers/[string id]/addresses() returns Address[]|http:Response {
        if !customers.hasKey(id) {
            return failure("NOT_FOUND", "customer not found", 404);
        }
        return customerAddresses[id] ?: [];
    }

    resource function get customers/[string id]/orders() returns json|http:Response {
        if !customers.hasKey(id) {
            return failure("NOT_FOUND", "customer not found", 404);
        }
        return [];
    }

    resource function get internal/customers/[string customerId]/addresses/[string addressId]/validate()
            returns json|http:Response {
        Address[]? list = customerAddresses[customerId];
        if list is () {
            return {valid: false, customerId, addressId, deliveryAddress: ()};
        }
        foreach Address address in list {
            if address.id == addressId {
                return {valid: true, customerId, addressId, deliveryAddress: address};
            }
        }
        return {valid: false, customerId, addressId, deliveryAddress: ()};
    }
}
