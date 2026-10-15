import ballerina/test;

@test:BeforeEach
function resetNotificationRepository() {
    clearNotifications();
}

@test:Config
function testNotificationDeliveryResult() returns error? {
    _ = check queueNotification({
                                    notificationId: "NOT-001",
                                    recipientType: CUSTOMER,
                                    recipientId: "CUS-001",
                                    channel: SMS,
                                    subject: "Order confirmed",
                                    message: "Your order is confirmed.",
                                    createdAt: "2026-08-17T12:00:00Z"
                                });
    Notification notification = check recordDeliveryResult("NOT-001", {
                                                                          successful: true,
                                                                          occurredAt: "2026-08-17T12:00:01Z"
                                                                      });
    test:assertEquals(notification.status, SENT);
}
