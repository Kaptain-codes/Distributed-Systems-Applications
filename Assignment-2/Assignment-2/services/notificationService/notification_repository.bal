isolated table<Notification> key(notificationId) notificationTable = table [];

isolated function memoryListNotifications(string? recipientId = ()) returns Notification[] {
    lock {
        Notification[] matchingNotifications = from Notification notification in notificationTable
            where recipientId is () || notification.recipientId == recipientId
            select notification.clone();
        return matchingNotifications.clone();
    }
}

// Queues an alert; channel delivery will later be driven by Kafka consumers.
isolated function memoryQueueNotification(NotificationRequest request)
        returns Notification|error {
    lock {
        NotificationRequest storedRequest = request.clone();
        if notificationTable.hasKey(storedRequest.notificationId) {
            return error(string `Notification '${storedRequest.notificationId}' already exists`);
        }
        Notification notification = {
            notificationId: storedRequest.notificationId,
            recipientType: storedRequest.recipientType,
            recipientId: storedRequest.recipientId,
            channel: storedRequest.channel,
            subject: storedRequest.subject,
            message: storedRequest.message,
            status: PENDING,
            createdAt: storedRequest.createdAt
        };
        notificationTable.add(notification);
        return notification.clone();
    }
}

// Stores the outcome of a simulated channel delivery attempt.
isolated function memoryRecordDeliveryResult(string notificationId, DeliveryResult result)
        returns Notification|error {
    lock {
        DeliveryResult storedResult = result.clone();
        Notification? notification = notificationTable[notificationId];
        if notification is () {
            return error(string `Notification '${notificationId}' was not found`);
        }
        if notification.status != PENDING {
            return error(string `Notification '${notificationId}' has already been handled`);
        }
        notification.status = storedResult.successful ? SENT : FAILED;
        notification.sentAt = storedResult.occurredAt;
        return notification.clone();
    }
}

public isolated function clearNotifications() {
    lock {
        notificationTable = table [];
    }
}

