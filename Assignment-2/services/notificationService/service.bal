// Notification HTTP API.
//
// Reached through the gateway at /api/notification/... ; inside Docker the
// service listens on port 9090.

import ballerina/http;
import ballerina/time;

configurable int port = 9090;

service /notification on new http:Listener(port) {

    function init() returns error? {
        check initNotificationPersistence();
        initializeNotificationRedisClient();
        return startNotificationKafkaRuntime();
    }

    resource function get health() returns json {
        return {status: "UP", 'service: "notification"};
    }

    // Every notification, as an object keyed by notification id.
    resource function get notifications() returns json|http:Response {
        map<Notification>|error result = notificationRepository.getAll();
        if result is error {
            return errorResponse(503, "DATABASE_ERROR", "notifications could not be loaded");
        }
        return result.toJson();
    }

    // Every notification for one customer or restaurant, as an array.
    resource function get notifications/[string recipientId]() returns json|http:Response {
        Notification[]|error result = notificationsFor(recipientId);
        if result is error {
            return errorResponse(503, "DATABASE_ERROR", "notifications could not be loaded");
        }
        return result.toJson();
    }

    // Marks a notification as read by stamping `readAt` with the current UTC time.
    resource function post notifications/[string id]/read() returns json|http:Response {
        Notification|error? itemResult = notificationRepository.getById(id);
        if itemResult is error {
            return errorResponse(503, "DATABASE_ERROR", "notification lookup failed");
        }
        Notification? item = itemResult;
        if item is () {
            return errorResponse(404, "NOT_FOUND", "notification was not found");
        }
        Notification updated = item.clone();
        updated.readAt = time:utcToString(time:utcNow());
        error? saved = notificationRepository.save(updated);
        if saved is error {
            return errorResponse(503, "DATABASE_ERROR", "notification could not be saved");
        }
        return updated;
    }
}

// Builds an error response with the `{error, message}` body used across the platform.
function errorResponse(int status, string code, string message) returns http:Response {
    http:Response response = new;
    response.statusCode = status;
    response.setJsonPayload({'error: code, message: message});
    return response;
}
