// notification-db: collections owned by the notification service, with validators and indexes.
// Runs once, when the container starts with an empty data volume.
db = db.getSiblingDB("food_delivery");

function ensureCollection(name, validator) {
    if (!db.getCollectionNames().includes(name)) {
        db.createCollection(name, {validator});
        return;
    }
    db.runCommand({collMod: name, validator});
}

ensureCollection("notifications", {$jsonSchema: {
    bsonType: "object",
    required: ["notificationId", "recipientType", "recipientId", "channel", "status"],
    properties: {
        notificationId: {bsonType: "string"},
        recipientType: {enum: ["CUSTOMER", "RESTAURANT", "DRIVER"]},
        channel: {enum: ["EMAIL", "SMS", "PUSH"]},
        status: {enum: ["PENDING", "SENT", "FAILED"]}
    }
}});

db.notifications.createIndex({notificationId: 1}, {unique: true});
db.notifications.createIndex({recipientId: 1, createdAt: -1});
