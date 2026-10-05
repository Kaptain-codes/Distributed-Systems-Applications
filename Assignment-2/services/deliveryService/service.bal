import ballerina/http;
import ballerina/time;
import ballerina/uuid;

type ErrorBody record {| string 'error; string message; |};
type Driver record {| string driverId; string name; string status = "AVAILABLE"; |};
type DriverRequest record {| string name; |};
type DriverStatusRequest record {| string status; |};
type Delivery record {| string deliveryId; string orderId; string pickupAddress; string deliveryAddress;
    string status = "ASSIGNED"; string? driverId = (); string? failureReason = ();
    string createdAt; string updatedAt; |};
type DeliveryRequest record {| string orderId; string pickupAddress; string deliveryAddress;
    string? driverId = (); |};
type FailureRequest record {| string reason; |};

map<Driver> drivers = {};
map<Delivery> deliveries = {};

service /delivery on new http:Listener(9090) {
    function init() returns error? {
        check initDeliveryDb();
        return startDeliveryKafkaRuntime();
    }

    resource function get health() returns json {
        return {status: "UP", 'service: "delivery"};
    }

    resource function post drivers(@http:Payload DriverRequest req) returns json|http:Response {
        if req.name.trim().length() == 0 {
            return errorResponse(400, "VALIDATION_ERROR", "driver name is required");
        }
        Driver driver = {driverId: uuid:createType4AsString(), name: req.name};
        error? created = dbCreateDriver(driver);
        if created is error { return errorResponse(503, "DATABASE_ERROR", "driver could not be created"); }
        return driver;
    }

    resource function get drivers/[string driverId]() returns json|http:Response {
        Driver|error? driverResult = dbDriver(driverId);
        if driverResult is error { return errorResponse(503, "DATABASE_ERROR", "driver lookup failed"); }
        Driver? driver = driverResult;
        if driver is () { return errorResponse(404, "NOT_FOUND", "driver was not found"); }
        return driver;
    }

    resource function put drivers/[string driverId]/status(@http:Payload DriverStatusRequest body)
            returns json|http:Response {
        Driver|error? currentResult = dbDriver(driverId);
        if currentResult is error { return errorResponse(503, "DATABASE_ERROR", "driver lookup failed"); }
        Driver? current = currentResult;
        if current is () { return errorResponse(404, "NOT_FOUND", "driver was not found"); }
        if body.status != "AVAILABLE" && body.status != "OFFLINE" && body.status != "BUSY" {
            return errorResponse(400, "VALIDATION_ERROR", "status must be AVAILABLE, OFFLINE or BUSY");
        }
        Driver next = current.clone();
        next.status = body.status;
        error? updated = dbSetDriverStatus(driverId, next.status);
        if updated is error { return errorResponse(503, "DATABASE_ERROR", "driver status could not be updated"); }
        return next;
    }

    resource function post deliveries(@http:Payload DeliveryRequest req) returns json|http:Response {
        if req.orderId.length() == 0 || req.pickupAddress.length() == 0 ||
            req.deliveryAddress.length() == 0 {
            return errorResponse(400, "VALIDATION_ERROR", "orderId and both addresses are required");
        }
        string? assigned = req.driverId;
        if assigned is string && dbDriver(assigned) is () {
            return errorResponse(400, "VALIDATION_ERROR", "driver was not registered");
        }
        string now = time:utcToString(time:utcNow());
        Delivery delivery = {deliveryId: uuid:createType4AsString(), orderId: req.orderId,
            pickupAddress: req.pickupAddress, deliveryAddress: req.deliveryAddress,
            status: assigned is string ? "ASSIGNED" : "UNASSIGNED", driverId: assigned,
            createdAt: now, updatedAt: now};
        error? saved = dbSaveDelivery(delivery);
        if saved is error { return errorResponse(503, "DATABASE_ERROR", "delivery could not be saved"); }
        return delivery;
    }

    resource function get deliveries/[string orderId]() returns json|http:Response {
        Delivery|error? deliveryResult = dbFindDelivery(orderId);
        if deliveryResult is error { return errorResponse(503, "DATABASE_ERROR", "delivery lookup failed"); }
        Delivery? delivery = deliveryResult;
        if delivery is () { return errorResponse(404, "NOT_FOUND", "delivery was not found"); }
        return delivery;
    }

    resource function post deliveries/[string orderId]/pickup(http:Request req) returns json|http:Response {
        return transition(orderId, req, "OUT_FOR_DELIVERY");
    }

    resource function post deliveries/[string orderId]/complete(http:Request req) returns json|http:Response {
        return transition(orderId, req, "COMPLETED");
    }

    resource function post deliveries/[string orderId]/'fail(http:Request req) returns json|http:Response {
        Delivery|error? currentResult = dbFindDelivery(orderId);
        if currentResult is error { return errorResponse(503, "DATABASE_ERROR", "delivery lookup failed"); }
        Delivery? current = currentResult;
        if current is () { return errorResponse(404, "NOT_FOUND", "delivery was not found"); }
        if current.status != "ASSIGNED" && current.status != "OUT_FOR_DELIVERY" {
            return errorResponse(409, "INVALID_STATE", "delivery cannot be failed in its current state");
        }
        http:Response|json result = validateDriver(current, req);
        if result is http:Response { return result; }
        json|error raw = req.getJsonPayload();
        string reason = "delivery failed";
        if raw is json {
            FailureRequest|error body = <FailureRequest>raw;
            if body is error || body.reason.trim().length() == 0 { return errorResponse(400, "VALIDATION_ERROR", "failure reason is required"); }
            reason = body.reason;
        } else if raw is error && raw.message().length() > 0 {
            return errorResponse(400, "VALIDATION_ERROR", "invalid failure body");
        }
        Delivery next = current.clone();
        next.status = "FAILED";
        next.failureReason = reason;
        next.updatedAt = time:utcToString(time:utcNow());
        error? saved = dbSaveDelivery(next);
        if saved is error { return errorResponse(503, "DATABASE_ERROR", "delivery could not be saved"); }
        return next;
    }
}

function findDeliveryByOrderId(string orderId) returns Delivery? {
    foreach Delivery delivery in deliveries {
        if delivery.orderId == orderId {
            return delivery;
        }
    }
    return ();
}

function transition(string orderId, http:Request req, string target) returns json|http:Response {
    Delivery? current = findDeliveryByOrderId(orderId);
    if current is () { return errorResponse(404, "NOT_FOUND", "delivery was not found"); }
    boolean valid = target == "OUT_FOR_DELIVERY" ? current.status == "ASSIGNED" :
        current.status == "OUT_FOR_DELIVERY";
    if !valid { return errorResponse(409, "INVALID_STATE", "delivery cannot make that transition"); }
    http:Response|json result = validateDriver(current, req);
    if result is http:Response { return result; }
    Delivery next = current.clone();
    next.status = target;
    next.updatedAt = time:utcToString(time:utcNow());
    error? saved = dbSaveDelivery(next);
    if saved is error { return errorResponse(503, "DATABASE_ERROR", "delivery could not be saved"); }
    string? assignedDriverId = next.driverId;
    if target == "COMPLETED" && assignedDriverId is string {
        string driverId = assignedDriverId;
        Driver|error? driverResult = dbDriver(driverId);
        Driver? driver = driverResult is Driver ? driverResult : ();
        if driver is Driver {
            error? released = dbSetDriverStatus(driverId, "AVAILABLE");
            if released is error { return errorResponse(503, "DATABASE_ERROR", "driver status could not be updated"); }
        }
    }
    string eventType = target == "OUT_FOR_DELIVERY" ? "delivery.picked_up" : "delivery.completed";
    error? published = publishManualDeliveryEvent(orderId, eventType, next);
    if published is error { return errorResponse(503, "PUBLISH_FAILED", eventType + " could not be published"); }
    return next;
}

function validateDriver(Delivery delivery, http:Request req) returns http:Response|json {
    string|error headerResult = req.getHeader("X-Driver-Id");
    if headerResult is error || headerResult.trim().length() == 0 {
        return errorResponse(400, "VALIDATION_ERROR", "X-Driver-Id header is required");
    }
    string header = headerResult;
    if delivery.driverId is () || delivery.driverId != header {
        return errorResponse(403, "FORBIDDEN", "driver is not assigned to this delivery");
    }
    Driver|error? driverResult = dbDriver(header);
    Driver? driver = driverResult is Driver ? driverResult : ();
    if driver is () || driver.status == "OFFLINE" {
        return errorResponse(409, "INVALID_STATE", "driver is not available");
    }
    return {};
}

function errorResponse(int status, string code, string message) returns http:Response {
    http:Response response = new;
    response.statusCode = status;
    response.setJsonPayload(<ErrorBody>{'error: code, message: message});
    return response;
}
