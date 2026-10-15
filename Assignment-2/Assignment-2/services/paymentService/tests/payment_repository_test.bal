import ballerina/test;

@test:BeforeEach
function resetPaymentRepository() {
    clearPayments();
}

@test:Config
function testApprovedPaymentCompletes() returns error? {
    _ = check createPayment({
                                paymentId: "PAY-001",
                                orderId: "ORD-001",
                                customerId: "CUS-001",
                                amount: 150.00,
                                requestedAt: "2026-08-17T12:00:00Z"
                            });
    Payment payment = check processPayment("PAY-001", {
                                                          approved: true,
                                                          processedAt: "2026-08-17T12:00:02Z"
                                                      });
    test:assertEquals(payment.status, COMPLETED);
}

@test:Config
function testPaymentCannotBeProcessedTwice() returns error? {
    _ = check createPayment({
                                paymentId: "PAY-002",
                                orderId: "ORD-002",
                                customerId: "CUS-001",
                                amount: 90.00,
                                requestedAt: "2026-08-17T12:00:00Z"
                            });
    _ = check processPayment("PAY-002", {approved: true, processedAt: "2026-08-17T12:00:02Z"});
    Payment|error secondDecision = processPayment("PAY-002", {
                                                                 approved: false,
                                                                 processedAt: "2026-08-17T12:00:03Z"
                                                             });
    test:assertTrue(secondDecision is error);
}
