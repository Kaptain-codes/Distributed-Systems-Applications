import ballerinax/mongodb;

public isolated function listPayments(string? orderId = ()) returns Payment[]|error {
    if databaseBackend == MONGODB {
        return mongoListPayments(orderId);
    }
    return memoryListPayments(orderId);
}

public isolated function findPayment(string paymentId) returns Payment?|error {
    if databaseBackend == MONGODB {
        return mongoFindPayment(paymentId);
    }
    return memoryFindPayment(paymentId);
}

public isolated function createPayment(PaymentRequest request) returns Payment|error {
    if databaseBackend == MONGODB {
        return mongoCreatePayment(request);
    }
    return memoryCreatePayment(request);
}

public isolated function processPayment(string paymentId, PaymentDecision decision)
        returns Payment|error {
    if databaseBackend == MONGODB {
        return mongoProcessPayment(paymentId, decision);
    }
    return memoryProcessPayment(paymentId, decision);
}

isolated function mongoListPayments(string? orderId) returns Payment[]|error {
    mongodb:Collection collection = check configuredMongoCollection("payments");
    map<json> filter = orderId is string ? {orderId} : {};
    stream<Payment, error?> paymentStream = check collection->find(filter, targetType = Payment);
    return from Payment payment in paymentStream
        select payment;
}

isolated function mongoFindPayment(string paymentId) returns Payment?|error {
    mongodb:Collection collection = check configuredMongoCollection("payments");
    return collection->findOne({paymentId}, targetType = Payment);
}

isolated function mongoCreatePayment(PaymentRequest request) returns Payment|error {
    if request.amount <= 0d {
        return error("Payment amount must be greater than zero");
    }
    Payment? existingPayment = check mongoFindPayment(request.paymentId);
    if existingPayment is Payment {
        return error(string `Payment '${request.paymentId}' already exists`);
    }
    Payment payment = {
        paymentId: request.paymentId,
        orderId: request.orderId,
        customerId: request.customerId,
        amount: request.amount,
        currency: request.currency,
        status: PENDING,
        requestedAt: request.requestedAt
    };
    mongodb:Collection collection = check configuredMongoCollection("payments");
    check collection->insertOne(payment);
    return payment;
}

isolated function mongoProcessPayment(string paymentId, PaymentDecision decision)
        returns Payment|error {
    mongodb:Collection collection = check configuredMongoCollection("payments");
    PaymentStatus resultingStatus = decision.approved ? COMPLETED : FAILED;
    string? failureReason = decision.approved ? () : decision.failureReason ?: "Payment was declined";
    mongodb:UpdateResult result = check collection->updateOne(
        {paymentId, status: PENDING},
        {set: {status: resultingStatus, processedAt: decision.processedAt, failureReason}}
    );
    if result.matchedCount == 0 {
        Payment? existingPayment = check mongoFindPayment(paymentId);
        if existingPayment is () {
            return error(string `Payment '${paymentId}' was not found`);
        }
        return error(string `Payment '${paymentId}' has already been processed`);
    }
    Payment? payment = check mongoFindPayment(paymentId);
    return payment is Payment ? payment : error(string `Payment '${paymentId}' was not found`);
}

