import ballerina/http;

configurable int servicePort = 9104;

isolated function paymentNotFound(string message) returns NotFoundResponse => {body: {message}};

isolated function paymentConflict(string message) returns ConflictResponse => {body: {message}};

isolated function invalidPayment(string message) returns BadRequestResponse => {body: {message}};

// Simulates payment processing while preserving an auditable payment state.
service /payments on new http:Listener(servicePort) {
    // Provides a lightweight readiness signal for container orchestration.
    isolated resource function get health() returns map<string> =>
        {status: "UP", component: "payment_service"};

    isolated resource function get .(string? orderId) returns Payment[]|error => listPayments(orderId);

    isolated resource function post .(PaymentRequest request)
            returns Payment|ConflictResponse|BadRequestResponse {
        Payment|error result = createPayment(request);
        if result is Payment {
            return result;
        }
        return result.message().includes("already exists") ? paymentConflict(result.message()) :
            invalidPayment(result.message());
    }

    isolated resource function get [string paymentId]() returns Payment|NotFoundResponse|error {
        Payment? payment = check findPayment(paymentId);
        return payment is Payment ? payment :
            paymentNotFound(string `Payment '${paymentId}' was not found`);
    }

    isolated resource function post [string paymentId]/process(PaymentDecision decision)
            returns Payment|NotFoundResponse|ConflictResponse|error {
        Payment|error result = processPayment(paymentId, decision);
        if result is Payment {
            check publishPaymentDecisionEvent(result);
            return result;
        }
        return result.message().includes("not found") ? paymentNotFound(result.message()) :
            paymentConflict(result.message());
    }
}

