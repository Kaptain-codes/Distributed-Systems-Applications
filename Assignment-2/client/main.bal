import ballerina/io;
import ballerina/lang.runtime;
import ballerina/log;

public function main(string... args) returns error? {
    ClientState state = loadState();
    if state.baseUrl != baseUrl || state.pollMs != pollMs {
        state.baseUrl = baseUrl;
        state.pollMs = pollMs;
    }
    if args.length() == 0 {
        printUsage();
        return;
    }
    string command = args[0];
    if command == "whoami" {
        check resolveIdentity(state);
    } else if command == "restaurants" {
        check listRestaurants(args);
    } else if command == "menu" {
        check listMenu(args);
    } else if command == "place" {
        check placeOrder(state, args);
    } else if command == "track" {
        check trackOrder(state, args);
    } else if command == "orders" {
        check listOrders(state);
    } else if command == "notifications" {
        check listNotifications(state);
    } else if command == "cancel" {
        check cancelOrder(state);
    } else if command == "settings" {
        check settings(state, args);
    } else if command == "simulate" {
        check simulate(state, args);
    } else if command == "auto-drive" {
        check autoDrive(state, args);
    } else {
        printUsage();
    }
}

function resolveIdentity(ClientState state) returns error? {
    string? customerId = state.customerId;
    if customerId is string {
        ApiResult|error result = apiFetch(apiClient, "GET",
            "/customer/customers/" + customerId);
        if result is ApiResult && result.status == 200 {
            io:println(stateSummary(state));
            return ();
        }
        if result is error || (result is ApiResult && result.status != 404) {
            return result is error ? result : error("customer validation failed");
        }
        state.customerId = ();
        state.addressId = ();
        state.address = ();
    }
    if !autoRegister {
        io:println("No customerId is configured. Set one with: settings set customer-id <id>");
        return ();
    }
    ApiResult|error customerResult = apiFetch(apiClient, "POST", "/customer/customers",
        buildRegisterCustomerPayload());
    if customerResult is error {
        return customerResult;
    }
    string? newCustomerId = readId(customerResult.body, "id", "customerId", "_id");
    if newCustomerId is () {
        io:println("[ERR] customer registration succeeded but no customer id was returned");
        printJson(customerResult.body);
        return error("backend contract error");
    }
    state.customerId = newCustomerId;
    ApiResult|error addressResult = apiFetch(apiClient, "POST",
        "/customer/customers/" + newCustomerId + "/addresses", buildAddressPayload());
    if addressResult is ApiResult && addressResult.status >= 200 && addressResult.status < 300 {
        state.addressId = readId(addressResult.body, "id", "addressId", "_id");
        state.address = addressResult.body;
    } else {
        io:println("[WARN] customer created; address registration failed. Retry with whoami.");
    }
    check saveState(state);
    io:println(stateSummary(state));
}

function listRestaurants(string[] args) returns error? {
    ApiResult|error result = apiFetch(apiClient, "GET", "/restaurant/restaurants");
    if result is error { return result; }
    if hasFlag(args, "--json") { printJson(result.body); } else { printList(result.body, "Restaurants"); }
}

function listMenu(string[] args) returns error? {
    string? restaurant = option(args, "--restaurant");
    if restaurant is () { return error("menu requires --restaurant <id>"); }
    ApiResult|error result = apiFetch(apiClient, "GET",
        "/restaurant/restaurants/" + restaurant + "/menu");
    if result is error { return result; }
    if hasFlag(args, "--json") { printJson(result.body); } else { printList(result.body, "Menu"); }
}

function placeOrder(ClientState state, string[] args) returns error? {
    check resolveIdentity(state);
    string? restaurant = option(args, "--restaurant");
    string? item = option(args, "--item");
    string? quantity = option(args, "--qty");
    string? address = option(args, "--address") ?: state.addressId;
    string payment = option(args, "--payment") ?: "SIM_OK";
    if restaurant is () || item is () || quantity is () || address is () || state.customerId is () {
        return error("place requires --restaurant, --item, --qty and a resolved address");
    }
    string restaurantId = check requireString(restaurant);
    string menuItemId = check requireString(item);
    string selectedAddressId = check requireString(address);
    string customerId = check requireString(state.customerId);
    string quantityValue = check requireString(quantity);
    int qty = check int:fromString(quantityValue);
    if qty < 1 { return error("qty must be at least 1"); }
    json payload = buildPlaceOrderPayload(customerId, restaurantId, selectedAddressId,
        menuItemId, qty, payment);
    ApiResult|error result = apiFetch(apiClient, "POST", "/order/orders", payload);
    if result is error { return result; }
    if result.status >= 200 && result.status < 300 {
        state.activeOrderId = readId(result.body, "orderId", "id", "_id");
        check saveState(state);
        io:println("order placed: " + (state.activeOrderId ?: "—"));
    }
}

function trackOrder(ClientState state, string[] args) returns error? {
    string? orderId = option(args, "--order") ?: state.activeOrderId;
    if orderId is () { return error("track requires --order <id> or an active order"); }
    boolean once = hasFlag(args, "--once");
    while true {
        ApiResult|error result = apiFetch(apiClient, "GET", "/order/orders/" + orderId);
        if result is error { return result; }
        if result.status == 200 { printOrder(result.body); }
        if once || isTerminal(result.body) { break; }
        runtime:sleep(<decimal>state.pollMs / 1000);
    }
}

function listOrders(ClientState state) returns error? {
    check resolveIdentity(state);
    if state.customerId is () { return error("customer identity is unavailable"); }
    string customerId = check requireString(state.customerId);
    ApiResult|error result = apiFetch(apiClient, "GET",
        "/order/orders?customerId=" + customerId);
    if result is error { return result; }
    printList(result.body, "Orders");
}

function listNotifications(ClientState state) returns error? {
    check resolveIdentity(state);
    if state.customerId is () { return error("customer identity is unavailable"); }
    string customerId = check requireString(state.customerId);
    ApiResult|error result = apiFetch(apiClient, "GET",
        "/notification/notifications?recipientId=" + customerId);
    if result is error { return result; }
    printList(result.body, "Notifications");
}

function cancelOrder(ClientState state) returns error? {
    if state.activeOrderId is () { return error("no active order"); }
    string orderId = check requireString(state.activeOrderId);
    ApiResult|error result = apiFetch(apiClient, "POST",
        "/order/orders/" + orderId + "/cancel");
    if result is error { return result; }
    printOrder(result.body);
}

function settings(ClientState state, string[] args) returns error? {
    if args.length() >= 2 && args[1] == "reset" {
        check clearState();
        io:println("Client state reset.");
        return;
    }
    if args.length() >= 4 && args[1] == "set" {
        if args[2] == "base-url" { state.baseUrl = args[3]; }
        else if args[2] == "poll-ms" { state.pollMs = check int:fromString(args[3]); }
        else if args[2] == "customer-id" { state.customerId = args[3]; }
        else { return error("unknown setting"); }
        check saveState(state);
        io:println("Setting saved.");
        return;
    }
    io:println(string `baseUrl=${state.baseUrl}\npollMs=${state.pollMs}\nstate=${statePath}`);
}

function simulate(ClientState state, string[] args) returns error? {
    if args.length() < 3 { return error("simulate requires kitchen or driver action"); }
    string area = args[1];
    string action = args[2];
    string? orderId = option(args, "--order");
    string? driverId = option(args, "--driver");
    string path = "";
    string method = "POST";
    json? body = ();
    if area == "kitchen" && orderId is string {
        path = "/restaurant/orders/" + orderId + "/" + action;
        if action == "reject" { body = {reason: option(args, "--reason") ?: "DECLINED"}; }
    } else if area == "driver" && action == "register" {
        ApiResult|error result = apiFetch(apiClient, "POST", "/delivery/drivers",
            buildRegisterDriverPayload(option(args, "--name") ?: "Demo Driver",
                option(args, "--phone") ?: "+264810000001"));
        if result is error { return result; }
        printJson(result.body);
        return;
    } else if area == "driver" && orderId is string && driverId is string {
        path = "/delivery/deliveries/" + orderId + "/" + action;
        map<string> headers = {"X-Driver-Id": driverId};
        ApiResult|error result = apiFetch(apiClient, method, path, body, headers);
        if result is error { return result; }
        printJson(result.body);
        return;
    } else {
        return error("invalid simulate command");
    }
    ApiResult|error result = apiFetch(apiClient, method, path, body);
    if result is error { return result; }
    printJson(result.body);
}

function autoDrive(ClientState state, string[] args) returns error? {
    string? orderId = option(args, "--order") ?: state.activeOrderId;
    if orderId is () { return error("auto-drive requires an active order"); }
    string[] steps = ["accept", "preparing", "ready"];
    foreach string step in steps {
        ApiResult|error result = apiFetch(apiClient, "POST",
            "/restaurant/orders/" + orderId + "/" + step);
        if result is error { return result; }
        io:println("auto-drive: " + step);
        runtime:sleep(3);
    }
    io:println("auto-drive: kitchen sequence complete; use a registered driver for pickup.");
}

function isTerminal(json orderData) returns boolean {
    string status = fieldText(orderData, "status");
    return status == "DELIVERED" || status == "CANCELLED";
}

function option(string[] args, string name) returns string? {
    foreach int index in 0 ..< args.length() {
        if args[index] == name && index + 1 < args.length() {
            return args[index + 1];
        }
    }
    return ();
}

function hasFlag(string[] args, string flag) returns boolean {
    foreach string arg in args {
        if arg == flag {
            return true;
        }

        function requireString(string? value) returns string|error {
            if value is string {
                return value;
            }
            return error("required value is missing");
        }
    }
    return false;
}

function printUsage() {
    io:println("Food Delivery Ballerina Client");
    io:println("Commands: whoami, restaurants, menu, place, track, orders, notifications,");
    io:println("         cancel, simulate, auto-drive, settings");
}
