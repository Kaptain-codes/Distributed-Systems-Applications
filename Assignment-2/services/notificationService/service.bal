// Notification HTTP API.
//
// Reached through the gateway at /api/notification/... ; inside Docker the
// service listens on port 9090.

import ballerina/http;
import ballerina/time;

configurable int port = 9090;

service /notification on new http:Listener(port) {

    function init() returns error? {
        return startNotificationKafkaRuntime();
    }

    resource function get health() returns json {
        return {status: "UP", 'service: "notification"};
    }

    // Every notification, as an object keyed by notification id.
    resource function get notifications() returns json {
        return notifications.toJson();
    }

    // Every notification for one customer or restaurant, as an array.
    resource function get notifications/[string recipientId]() returns json {
        return notificationsFor(recipientId);
    }

    // Marks a notification as read by stamping `readAt` with the current UTC time.
    resource function post notifications/[string id]/read() returns json|http:Response {
        Notification? item = notifications[id];
        if item is () {
            return errorResponse(404, "NOT_FOUND", "notification was not found");
        }
        Notification updated = item.clone();
        updated.readAt = time:utcToString(time:utcNow());
        notifications[id] = updated;
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
