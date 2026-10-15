import ballerina/http;

configurable int servicePort = 9106;

isolated function notificationNotFound(string message) returns NotFoundResponse => {body: {message}};

isolated function notificationConflict(string message) returns ConflictResponse => {body: {message}};

// Queues and tracks customer, restaurant, and driver notifications.
service /notifications on new http:Listener(servicePort) {
    // Provides a lightweight readiness signal for container orchestration.
    isolated resource function get health() returns map<string> =>
        {status: "UP", component: "notification_service"};

    isolated resource function get .(string? recipientId) returns Notification[]|error =>
        listNotifications(recipientId);

    isolated resource function post .(NotificationRequest request)
            returns Notification|ConflictResponse {
        Notification|error result = queueNotification(request);
        return result is error ? notificationConflict(result.message()) : result;
    }

    isolated resource function post [string notificationId]/delivery_result(DeliveryResult result)
            returns Notification|NotFoundResponse|ConflictResponse {
        Notification|error update = recordDeliveryResult(notificationId, result);
        if update is Notification {
            return update;
        }
        return update.message().includes("not found") ? notificationNotFound(update.message()) :
            notificationConflict(update.message());
    }
}

