// order-db: collections owned by the order service, with validators and indexes.
// Runs once, when the container starts with an empty data volume.
db = db.getSiblingDB("food_delivery");

function ensureCollection(name, validator) {
    if (!db.getCollectionNames().includes(name)) {
        db.createCollection(name, {validator});
        return;
    }
    db.runCommand({collMod: name, validator});
}

ensureCollection("orders", {$jsonSchema: {
    bsonType: "object",
    required: ["orderId", "customerId", "restaurantId", "items", "totalAmount", "status"],
    properties: {
        orderId: {bsonType: "string"},
        status: {enum: ["CREATED", "CONFIRMED", "PREPARING", "READY", "OUT_FOR_DELIVERY", "DELIVERED", "CANCELLED"]},
        items: {bsonType: "array"}
    }
}});

db.orders.createIndex({orderId: 1}, {unique: true});
db.orders.createIndex({customerId: 1, createdAt: -1});
db.orders.createIndex({restaurantId: 1, status: 1});
