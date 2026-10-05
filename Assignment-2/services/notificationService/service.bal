import ballerina/http;
import ballerina/time;
import ballerina/uuid;

configurable int port = 9090;

type Notification record {|
    string id;
    string recipientType;
    string recipientId;
    string orderId;
    string channel;
    string notificationType;
    string message;
    string status = "SENT";
    string sourceEventId;
    string createdAt;
    string? readAt = ();
|};

map<Notification> notifications = {};

service /notification on new http:Listener(port) {
    function init() returns error? {
        return startNotificationKafkaRuntime();
    }

    resource function get health() returns json {
        return {status: "UP", 'service: "notification"};
    }

    resource function get notifications() returns json {
        return notifications.toJson();
    }

    resource function get notifications/[string recipientId]() returns json {
        json[] result = [];
        foreach Notification item in notifications {
            if item.recipientId == recipientId {
                result.push(item);
            }
        }
        return result;
    }

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

function errorResponse(int status, string code, string message) returns http:Response {
    http:Response response = new;
    response.statusCode = status;
    response.setJsonPayload({'error: code, message: message});
    return response;
}

function addNotification(string recipientType, string recipientId, string orderId,
        string sourceEventId, string message) returns Notification {
    Notification item = {
        id: uuid:createType4AsString(), recipientType: recipientType, recipientId: recipientId,
        orderId: orderId, channel: "IN_APP", notificationType: "ORDER_STATUS",
        message: message, sourceEventId: sourceEventId, createdAt: time:utcToString(time:utcNow())
    };
    notifications[item.id] = item;
    return item;
}
