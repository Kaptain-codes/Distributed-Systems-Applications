// In-memory notification store.
//
// Notifications live only in this map, so they are lost when the container
// restarts. Every write goes through `addNotification`.

import ballerina/time;
import ballerina/uuid;

// Recipient types written on each notification.
const string RECIPIENT_CUSTOMER = "CUSTOMER";
const string RECIPIENT_RESTAURANT = "RESTAURANT";

// Values every notification currently gets.
const string CHANNEL_IN_APP = "IN_APP";
const string TYPE_ORDER_STATUS = "ORDER_STATUS";

// A single notification as stored and returned by the HTTP API.
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

// All notifications, keyed by notification id.
map<Notification> notifications = {};

# Creates an in-app order-status notification and stores it.
#
# + recipientType - `CUSTOMER` or `RESTAURANT`
# + recipientId - customer or restaurant id the notification is for
# + orderId - order the notification is about
# + sourceEventId - id of the Kafka event that caused it
# + message - text shown to the recipient
# + return - the stored notification
function addNotification(string recipientType, string recipientId, string orderId,
        string sourceEventId, string message) returns Notification {
    Notification item = {
        id: uuid:createType4AsString(),
        recipientType: recipientType,
        recipientId: recipientId,
        orderId: orderId,
        channel: CHANNEL_IN_APP,
        notificationType: TYPE_ORDER_STATUS,
        message: message,
        sourceEventId: sourceEventId,
        createdAt: time:utcToString(time:utcNow())
    };
    notifications[item.id] = item;
    return item;
}

// Returns every notification addressed to one recipient.
//
// + recipientId - customer or restaurant id
// + return - matching notifications, in store order
function notificationsFor(string recipientId) returns json[] {
    json[] result = [];
    foreach Notification item in notifications {
        if item.recipientId == recipientId {
            result.push(item);
        }
    }
    return result;
}
