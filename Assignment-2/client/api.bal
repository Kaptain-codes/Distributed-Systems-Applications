import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;

isolated function apiFetch(http:Client api, string method, string path, json? body = (),
        map<string> extraHeaders = {}) returns ApiResult|error {
    string url = baseUrl + path;
    http:Request request = new;
    request.setHeader("Accept", "application/json");
    if body is json {
        request.setJsonPayload(body);
        request.setHeader("Content-Type", "application/json");
    }
    foreach var [key, value] in extraHeaders.entries() {
        request.setHeader(key, value);
    }
    if idempotencyEnabled && method == "POST" &&
            (path == "/order/orders" || path.endsWith("/cancel")) {
        string key = uuid:createType4AsString();
        request.setHeader("Idempotency-Key", key);
    }
    http:Response|error response;
    if method == "GET" {
        response = api->get(path);
    } else if method == "POST" {
        response = api->post(path, request);
    } else if method == "PUT" {
        response = api->put(path, request);
    } else {
        return error("unsupported HTTP method: " + method);
    }
    if response is error {
        return error(string `cannot reach ${url}: ${response.message()}`);
    }
    json responseBody = {};
    json|error parsed = response.getJsonPayload();
    if parsed is json {
        responseBody = parsed;
    } else {
        string|error text = response.getTextPayload();
        if text is string && text.length() > 0 {
            responseBody = text;
        }
    }
    if response.statusCode < 200 || response.statusCode >= 300 {
        string message = responseBody is map<json> && responseBody["message"] is string
            ? <string>responseBody["message"] : "request failed";
        io:println(string `[ERR] status=${response.statusCode} url=${url} message="${message}"`);
    }
    return {status: response.statusCode, body: responseBody, url};
}

isolated function readId(json resp, string... candidates) returns string? {
    json[] locations = [resp];
    if resp is map<json> {
        if resp["data"] is json { locations.push(<json>resp["data"]); }
        if resp["body"] is json { locations.push(<json>resp["body"]); }
    }
    foreach json location in locations {
        if location is map<json> {
            foreach string candidate in candidates {
                json? value = location[candidate];
                if value is string {
                    return value;
                }
                if value is int {
                    return value.toString();
                }
                if value is decimal {
                    return value.toString();
                }
            }
        }
    }
    log:printError("response did not contain a server-generated id", idResponse = resp);
    return ();
}

isolated function buildRegisterCustomerPayload() returns json {
    return {
        name: "Demo Customer",
        email: "demo+" + time:utcNow()[0].toString() + "@example.com",
        phone: "+264810000000"
    };
}

isolated function buildAddressPayload() returns json {
    return {label: "Home", line1: "1 Demo Street", city: "Windhoek",
        region: "Khomas", is_default: true};
}

isolated function buildPlaceOrderPayload(string customerId, string restaurantId,
        string addressId, string menuItemId, int qty, string paymentMethod) returns json {
    return {
        customerId,
        restaurantId,
        addressId,
        items: [{menuItemId, qty}],
        paymentMethod
    };
}

isolated function buildRegisterDriverPayload(string name, string phone) returns json {
    return {name, phone};
}
