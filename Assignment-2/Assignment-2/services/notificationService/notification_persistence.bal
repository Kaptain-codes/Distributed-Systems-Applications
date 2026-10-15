import ballerinax/mongodb;

public isolated function listNotifications(string? recipientId = ()) returns Notification[]|error {
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("notifications");
        map<json> filter = recipientId is string ? {recipientId} : {};
        stream<Notification, error?> notificationStream =
            check collection->find(filter, targetType = Notification);
        return from Notification notification in notificationStream
            select notification;
    }
    return memoryListNotifications(recipientId);
}

public isolated function queueNotification(NotificationRequest request)
        returns Notification|error {
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("notifications");
        Notification? existing = check collection->findOne(
            {notificationId: request.notificationId}, targetType = Notification);
        if existing is Notification {
            return error(string `Notification '${request.notificationId}' already exists`);
        }
        Notification notification = notificationFromRequest(request);
        check collection->insertOne(notification);
        return notification;
    }
    return memoryQueueNotification(request);
}

public isolated function recordDeliveryResult(string notificationId, DeliveryResult result)
        returns Notification|error {
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("notifications");
        NotificationStatus status = result.successful ? SENT : FAILED;
        mongodb:UpdateResult update = check collection->updateOne(
            {notificationId, status: PENDING}, {set: {status, sentAt: result.occurredAt}});
        if update.matchedCount == 0 {
            return notificationUpdateFailure(collection, notificationId);
        }
        Notification? notification = check collection->findOne({notificationId}, targetType = Notification);
        return notification is Notification ? notification :
            error(string `Notification '${notificationId}' was not found`);
    }
    return memoryRecordDeliveryResult(notificationId, result);
}

isolated function notificationFromRequest(NotificationRequest request) returns Notification => {
    notificationId: request.notificationId,
    recipientType: request.recipientType,
    recipientId: request.recipientId,
    channel: request.channel,
    subject: request.subject,
    message: request.message,
    status: PENDING,
    createdAt: request.createdAt
};

isolated function notificationUpdateFailure(mongodb:Collection collection, string notificationId)
        returns Notification|error {
    Notification? existing = check collection->findOne({notificationId}, targetType = Notification);
    return existing is () ? error(string `Notification '${notificationId}' was not found`) :
        error(string `Notification '${notificationId}' has already been handled`);
}

