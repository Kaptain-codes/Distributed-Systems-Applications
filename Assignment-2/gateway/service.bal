import ballerina/http;
import ballerina/log;
import ballerina/url;

configurable int port = 8080;
configurable string orderService = "http://order-service:9090";
configurable string customerService = "http://customer-service:9090";
configurable string notificationService = "http://notification-service:9090";
configurable string paymentService = "http://payment-service:9090";
configurable string adminService = "http://admin-service:9090";
configurable string deliveryService = "http://delivery-service:9090";
configurable string restaurantService = "http://restaurant-service:9090";
configurable decimal downstreamTimeout = 10;

final http:Client orderClient = check new (orderService, {timeout: downstreamTimeout});
final http:Client customerClient = check new (customerService, {timeout: downstreamTimeout});
final http:Client notificationClient = check new (notificationService, {timeout: downstreamTimeout});
final http:Client paymentClient = check new (paymentService, {timeout: downstreamTimeout});
final http:Client adminClient = check new (adminService, {timeout: downstreamTimeout});
final http:Client deliveryClient = check new (deliveryService, {timeout: downstreamTimeout});
final http:Client restaurantClient = check new (restaurantService, {timeout: downstreamTimeout});

@http:ServiceConfig {
    cors: {
        allowOrigins: [
            "http://localhost:5500",
            "http://localhost:5502",
            "http://127.0.0.1:5500",
            "http://127.0.0.1:5502"
        ],
        allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allowHeaders: ["Accept", "Content-Type", "Idempotency-Key", "X-Driver-Id"],
        exposeHeaders: ["Content-Type"],
        allowCredentials: false,
        maxAge: 3600
    }
}
service /api on new http:Listener(port) {
    resource function get health() returns json {
        return {status: "UP", 'service: "gateway"};
    }

    resource function get orders() returns json|http:Response {
        return forward("GET", "order", ["orders"], ());
    }

    resource function get orders/[string id]() returns json|http:Response {
        return forward("GET", "order", ["orders", id], ());
    }

    resource function post orders(http:Request req) returns json|http:Response {
        return dispatchRequest("POST", "order", ["orders"], req);
    }

    resource function get [string serviceName]/[string... path](http:Request req)
            returns json|http:Response {
        return forward("GET", serviceName, path, req);
    }

    resource function post [string serviceName]/[string... path](http:Request req)
            returns json|http:Response {
        return dispatchRequest("POST", serviceName, path, req);
    }

    resource function put [string serviceName]/[string... path](http:Request req)
            returns json|http:Response {
        return forward("PUT", serviceName, path, req);
    }

    resource function patch [string serviceName]/[string... path](http:Request req)
            returns json|http:Response {
        return forward("PATCH", serviceName, path, req);
    }

    resource function delete [string serviceName]/[string... path](http:Request req)
            returns json|http:Response {
        return forward("DELETE", serviceName, path, req);
    }
}

function dispatchRequest(string method, string serviceName, string[] path, http:Request req)
        returns json|http:Response {
    if shouldUseIdempotency(method, serviceName, path) {
        return forwardWithIdempotency(method, serviceName, path, req);
    }
    return forward(method, serviceName, path, req);
}

function shouldUseIdempotency(string method, string serviceName, string[] path) returns boolean {
    if method != "POST" {
        return false;
    }
    if serviceName == "order" && (path == ["orders"] ||
            (path.length() == 3 && path[0] == "orders" && path[2] == "cancel")) {
        return true;
    }
    return serviceName == "restaurant" && path.length() == 3 && path[0] == "orders" &&
        (path[2] == "accept" || path[2] == "reject" ||
        path[2] == "preparing" || path[2] == "ready");
}

function forwardWithIdempotency(string method, string serviceName, string[] path, http:Request req)
        returns json|http:Response {
    string|error keyResult = req.getHeader("Idempotency-Key");
    if keyResult is error || keyResult == "" {
        return forward(method, serviceName, path, req);
    }
    string key = keyResult;
    if !validIdempotencyKey(key) {
        return errorResponse(400, "INVALID_IDEMPOTENCY_KEY", "Idempotency-Key must be a UUID");
    }
    if !redisAvailable() {
        log:printWarn("Redis unavailable; forwarding idempotent request without deduplication");
        return forward(method, serviceName, path, req);
    }
    string|error payload = req.getTextPayload();
    if payload is error {
        return errorResponse(400, "INVALID_REQUEST", "request body could not be read");
    }
    string body = payload;
    string canonicalPath = "/" + serviceName;
    foreach string segment in path {
        canonicalPath += "/" + segment;
    }
    string cacheKey = idempotencyKey(serviceName, method, canonicalPath, key);
    string hash = requestHash(method, canonicalPath, body);
    IdempotencyEntry|error? cached = loadIdempotency(cacheKey);
    if cached is IdempotencyEntry {
        if cached.requestHash != hash {
            return errorResponse(409, "IDEMPOTENCY_CONFLICT", "key was reused with a different request");
        }
        if cached.status != 0 {
            http:Response cachedResponse = new;
            cachedResponse.statusCode = cached.status;
            cachedResponse.setJsonPayload(cached.body);
            return cachedResponse;
        }
        return errorResponse(409, "IDEMPOTENCY_IN_FLIGHT", "request with this key is already in progress");
    }
    boolean|error reserved = reserveIdempotency(cacheKey, hash);
    if reserved is error || !reserved {
        log:printWarn("Redis idempotency reservation failed; forwarding request");
        return forward(method, serviceName, path, req);
    }
    json|http:Response result = forward(method, serviceName, path, req);
    if result is json {
        if result is map<json> {
            error? saveResult = saveIdempotency(cacheKey, 200, result, hash);
            if saveResult is error {
                log:printWarn("Redis idempotency response save failed");
            }
        }
    } else {
        json|error responseBody = result.getJsonPayload();
        if responseBody is json {
            error? saveResult = saveIdempotency(cacheKey, result.statusCode, responseBody, hash);
            if saveResult is error {
                log:printWarn("Redis idempotency response save failed");
            }
        }
    }
    return result;
}

function forward(string method, string domain, string[] path, http:Request? request)
        returns json|http:Response {
    if !isPublicPath(path) {
        return errorResponse(404, "NOT_FOUND", "internal endpoints are not public");
    }
    http:Client? selected = clientFor(domain);
    if selected is () {
        return errorResponse(404, "NOT_FOUND", "unknown API domain");
    }
    string target = targetFor(domain, path);
    if request is http:Request {
        map<string[]> params = request.getQueryParams();
        boolean first = true;
        foreach var [name, values] in params.entries() {
            foreach string value in values {
                string|url:Error encodedName = url:encode(name, "UTF-8");
                string|url:Error encodedValue = url:encode(value, "UTF-8");
                if encodedName is string && encodedValue is string {
                    target += first ? "?" : "&";
                    target += encodedName + "=" + encodedValue;
                    first = false;
                }
            }
        }
    }
    http:Response|error result;
    http:Request outbound = request is http:Request ? outboundRequest(request) : new;
    if method == "GET" {
        result = selected->get(target);
    } else if method == "POST" {
        result = selected->post(target, outbound);
    } else if method == "PUT" {
        result = selected->put(target, outbound);
    } else if method == "PATCH" {
        result = selected->patch(target, outbound);
    } else {
        result = selected->delete(target, outbound);
    }

    if result is error {
        string message = result.message();
        if transportStatus(result) == 503 {
            return errorResponse(503, "SERVICE_UNAVAILABLE", message);
        }
        return errorResponse(502, "BAD_GATEWAY", message);
    }

    return result;
}

function outboundRequest(http:Request inbound) returns http:Request {
    http:Request outbound = new;
    string|error body = inbound.getTextPayload();
    if body is string && body.length() > 0 {
        string|error contentType = inbound.getHeader("Content-Type");
        if contentType is string {
            outbound.setTextPayload(body, contentType);
        } else {
            outbound.setTextPayload(body);
        }
    }
    foreach string headerName in ["Content-Type", "Idempotency-Key", "X-Correlation-Id", "X-Driver-Id"] {
        string|error headerValue = inbound.getHeader(headerName);
        if headerValue is string {
            outbound.setHeader(headerName, headerValue);
        }
    }
    return outbound;
}

function targetFor(string domain, string[] path) returns string {
    string target = "/" + domain;
    foreach string segment in path {
        target += "/" + segment;
    }
    return target;
}

function isPublicPath(string[] path) returns boolean {
    foreach string segment in path {
        if segment == "internal" {
            return false;
        }
    }
    return true;
}

function transportStatus(error err) returns int {
    string message = err.message().toLowerAscii();
    return message.includes("connect") || message.includes("timeout") ? 503 : 502;
}

function clientFor(string domain) returns http:Client? {
    if domain == "order" {
        return orderClient;
    } else if domain == "customer" {
        return customerClient;
    } else if domain == "notification" {
        return notificationClient;
    } else if domain == "payment" {
        return paymentClient;
    } else if domain == "admin" {
        return adminClient;
    } else if domain == "delivery" {
        return deliveryClient;
    } else if domain == "restaurant" {
        return restaurantClient;
    }
    return ();
}

function errorResponse(int status, string code, string message) returns http:Response {
    http:Response response = new;
    response.statusCode = status;
    response.setJsonPayload({'error: code, message: message});
    return response;
}
