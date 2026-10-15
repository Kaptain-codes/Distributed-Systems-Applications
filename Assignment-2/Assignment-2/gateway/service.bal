import ballerina/http;

// API Gateway - single REST entry point for the service APIs.

configurable int port = 8080;

// These resolve via Docker's internal DNS on the `backbone` network — the
// service name IS the hostname, and 9090 is what every service actually
// listens on internally (host-side 8081-8087 mappings are only for
// reaching them from outside Docker, e.g. from your own machine).
configurable string orderService = "http://order-service:9090";
configurable string customerService = "http://customer-service:9090";
configurable string notificationService = "http://notification-service:9090";
configurable string paymentService = "http://payment-service:9090";
configurable string adminService = "http://admin-service:9090";
configurable string deliveryService = "http://delivery-service:9090";
configurable string restaurantService = "http://restaurant-service:9090";

final http:Client orderClient = check new (orderService);
final http:Client customerClient = check new (customerService);
final http:Client notificationClient = check new (notificationService);
final http:Client paymentClient = check new (paymentService);
final http:Client adminClient = check new (adminService);
final http:Client deliveryClient = check new (deliveryService);
final http:Client restaurantClient = check new (restaurantService);

// First path segment after /api -> [downstream client, base path on that service].
// Singular aliases are accepted so /api/order/... and /api/orders/... both work.
function route(string segment) returns [http:Client, string]? {
    match segment {
        "orders"|"order" => {
            return [orderClient, "/orders"];
        }
        "customers"|"customer" => {
            return [customerClient, "/customers"];
        }
        "restaurants"|"restaurant" => {
            return [restaurantClient, "/restaurants"];
        }
        "payments"|"payment" => {
            return [paymentClient, "/payments"];
        }
        "delivery"|"deliveries" => {
            return [deliveryClient, "/delivery"];
        }
        "notifications"|"notification" => {
            return [notificationClient, "/notifications"];
        }
        "admin" => {
            return [adminClient, "/admin"];
        }
    }
    return ();
}

function errorResponse(int status, string message) returns http:Response {
    http:Response res = new;
    res.statusCode = status;
    res.setJsonPayload({message});
    return res;
}

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allowHeaders: ["*"]
    }
}
service /api on new http:Listener(port) {

    resource function get health() returns json {
        return {status: "UP", 'service: "gateway"};
    }

    // Reverse proxy: /api/{service}/{rest...}?{query} -> {service base path}/{rest...}?{query},
    // for every HTTP method, passing status codes and bodies straight through.
    resource function 'default [string... path](http:Request req) returns http:Response {
        if path.length() == 0 {
            return errorResponse(404, "Unknown route. Try /api/orders, /api/restaurants, /api/customers ...");
        }
        [http:Client, string]? target = route(path[0]);
        if target is () {
            return errorResponse(404, string `No service handles '/api/${path[0]}'`);
        }
        var [downstream, basePath] = target;

        // Everything after "/api/{segment}" in the raw path, including any query string.
        string rest = req.rawPath.substring(("/api/" + path[0]).length());
        http:Response|error res = downstream->forward(basePath + rest, req);
        if res is error {
            return errorResponse(502, string `${path[0]} service unavailable: ${res.message()}`);
        }
        return res;
    }
}
