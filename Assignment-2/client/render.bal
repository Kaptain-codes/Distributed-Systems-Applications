import ballerina/io;

function printJson(json value) {
    io:println(value.toJsonString());
}

function printList(json value, string title) {
    io:println("\n" + title);
    if value is json[] {
        int index = 1;
        foreach json item in value {
            io:println(string `${index}. ${item.toJsonString()}`);
            index += 1;
        }
    } else {
        printJson(value);
    }
}

function printOrder(json orderData) {
    string orderId = fieldText(orderData, "orderId", "id", "_id");
    string status = fieldText(orderData, "status");
    string paymentStatus = fieldText(orderData, "paymentStatus");
    io:println(string `\norder ${orderId}  status=${status}  payment=${paymentStatus}`);
    io:println("[✓] CREATED  [✓] CONFIRMED  [▶] " + status +
        "  [ ] READY  [ ] OUT_FOR_DELIVERY  [ ] DELIVERED");
    if orderData is map<json> && orderData["cancellationReason"] is string {
        io:println("CANCELLED: " + <string>orderData["cancellationReason"]);
    }
}

function fieldText(json value, string... names) returns string {
    if value is map<json> {
        foreach string name in names {
            json? candidate = value[name];
            if candidate is string {
                return candidate;
            }
            if candidate is int {
                return candidate.toString();
            }
            if candidate is decimal {
                return candidate.toString();
            }
        }
    }
    return "—";
}
