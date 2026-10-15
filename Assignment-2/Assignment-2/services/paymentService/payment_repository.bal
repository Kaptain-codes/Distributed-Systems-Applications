isolated table<Payment> key(paymentId) paymentTable = table [];

isolated function memoryListPayments(string? orderId = ()) returns Payment[] {
    lock {
        Payment[] matchingPayments = from Payment payment in paymentTable
            where orderId is () || payment.orderId == orderId
            select payment.clone();
        return matchingPayments.clone();
    }
}

isolated function memoryFindPayment(string paymentId) returns Payment? {
    lock {
        Payment? payment = paymentTable[paymentId];
        return payment is Payment ? payment.clone() : ();
    }
}

// Opens a pending payment after validating the monetary amount.
isolated function memoryCreatePayment(PaymentRequest request) returns Payment|error {
    lock {
        PaymentRequest storedRequest = request.clone();
        if paymentTable.hasKey(storedRequest.paymentId) {
            return error(string `Payment '${storedRequest.paymentId}' already exists`);
        }
        if storedRequest.amount <= 0d {
            return error("Payment amount must be greater than zero");
        }
        Payment payment = {
            paymentId: storedRequest.paymentId,
            orderId: storedRequest.orderId,
            customerId: storedRequest.customerId,
            amount: storedRequest.amount,
            currency: storedRequest.currency,
            status: PENDING,
            requestedAt: storedRequest.requestedAt
        };
        paymentTable.add(payment);
        return payment.clone();
    }
}

// Completes the one-time simulated gateway decision atomically.
isolated function memoryProcessPayment(string paymentId, PaymentDecision decision)
        returns Payment|error {
    lock {
        PaymentDecision storedDecision = decision.clone();
        Payment? payment = paymentTable[paymentId];
        if payment is () {
            return error(string `Payment '${paymentId}' was not found`);
        }
        if payment.status != PENDING {
            return error(string `Payment '${paymentId}' has already been processed`);
        }
        payment.status = storedDecision.approved ? COMPLETED : FAILED;
        payment.processedAt = storedDecision.processedAt;
        payment.failureReason = storedDecision.approved ? () :
            storedDecision.failureReason ?: "Payment was declined";
        return payment.clone();
    }
}

public isolated function clearPayments() {
    lock {
        paymentTable = table [];
    }
}

