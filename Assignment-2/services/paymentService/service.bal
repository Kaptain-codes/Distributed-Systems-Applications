import ballerina/http;
import ballerina/time;
import ballerina/uuid;

type ErrorBody record {| string 'error; string message; |};
public type Payment record {| string paymentId; string orderId; decimal amount; string currency = "NAD";
    string method = "CARD"; string status = "PENDING"; string createdAt; string updatedAt; |};
type PaymentRequest record {| string orderId; decimal amount; string currency = "NAD";
    string method = "CARD"; string? customerId = (); |};
type SimulationRequest record {| boolean success = true; string? reason = (); |};

service /payment on new http:Listener(9090) {
    function init() returns error? {
        check initPaymentRepository();
        initializePaymentRedisClient();
        return startPaymentKafkaRuntime();
    }

    resource function get health() returns json {
        return {status: "UP", 'service: "payment"};
    }

    resource function post payments(@http:Payload PaymentRequest req) returns json|http:Response {
        if req.orderId.length() == 0 || req.amount <= <decimal>0 ||
            req.currency != "NAD" || req.method.length() == 0 {
            return errorResponse(400, "VALIDATION_ERROR", "orderId, a positive amount, currency NAD and method are required");
        }
        string now = time:utcToString(time:utcNow());
        Payment payment = {paymentId: uuid:createType4AsString(), orderId: req.orderId,
            amount: req.amount, currency: req.currency, method: req.method, createdAt: now, updatedAt: now};
        error? saved = paymentRepository.save(payment, req.customerId);
        if saved is error { return errorResponse(503, "DATABASE_ERROR", "payment could not be saved"); }
        return payment;
    }

    resource function get [string paymentId]() returns json|http:Response {
        Payment|error? paymentResult = paymentRepository.getById(paymentId);
        if paymentResult is error { return errorResponse(503, "DATABASE_ERROR", "payment lookup failed"); }
        Payment? payment = paymentResult;
        if payment is () { return errorResponse(404, "NOT_FOUND", "payment was not found"); }
        return payment;
    }

    resource function get payments/[string orderId]() returns json|http:Response {
        return lookupByOrderId(orderId);
    }

    resource function post [string paymentId]/simulate(http:Request req) returns json|http:Response {
        Payment|error? currentResult = paymentRepository.getById(paymentId);
        if currentResult is error { return errorResponse(503, "DATABASE_ERROR", "payment lookup failed"); }
        Payment? current = currentResult;
        if current is () { return errorResponse(404, "NOT_FOUND", "payment was not found"); }
        if current.status != "PENDING" {
            return errorResponse(409, "INVALID_STATE", "only pending payments can be simulated");
        }
        json|error raw = req.getJsonPayload();
        SimulationRequest simulation = {success: true};
        if raw is json {
            SimulationRequest|error candidate = <SimulationRequest>raw;
            if candidate is error { return errorResponse(400, "VALIDATION_ERROR", "invalid simulation body"); }
            simulation = candidate;
        }
        Payment next = current.clone();
        next.status = simulation.success ? "COMPLETED" : "FAILED";
        next.updatedAt = time:utcToString(time:utcNow());
        error? saved = paymentRepository.save(next);
        if saved is error { return errorResponse(503, "DATABASE_ERROR", "payment could not be saved"); }
        return next;
    }
}

function lookupByOrderId(string orderId) returns json|http:Response {
    Payment|error? paymentResult = paymentRepository.getByOrderId(orderId);
    if paymentResult is error { return errorResponse(503, "DATABASE_ERROR", "payment lookup failed"); }
    Payment? payment = paymentResult;
    if payment is Payment { return payment; }
    return errorResponse(404, "NOT_FOUND", "payment was not found");
}

function errorResponse(int status, string code, string message) returns http:Response {
    http:Response response = new;
    response.statusCode = status;
    response.setJsonPayload(<ErrorBody>{'error: code, message: message});
    return response;
}
