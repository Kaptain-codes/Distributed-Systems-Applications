// delivery-db: collections owned by the delivery service, with validators and indexes.
// Runs once, when the container starts with an empty data volume.
db = db.getSiblingDB("food_delivery");

function ensureCollection(name, validator) {
    if (!db.getCollectionNames().includes(name)) {
        db.createCollection(name, {validator});
        return;
    }
    db.runCommand({collMod: name, validator});
}

ensureCollection("drivers", {$jsonSchema: {
    bsonType: "object",
    required: ["driverId", "fullName", "phoneNumber", "vehicleRegistration", "status"],
    properties: {
        driverId: {bsonType: "string"},
        status: {enum: ["AVAILABLE", "ASSIGNED", "OFFLINE"]}
    }
}});

ensureCollection("deliveries", {$jsonSchema: {
    bsonType: "object",
    required: ["deliveryId", "orderId", "driverId", "status", "assignedAt", "updatedAt"],
    properties: {
        deliveryId: {bsonType: "string"},
        status: {enum: ["ASSIGNED", "PICKED_UP", "IN_TRANSIT", "DELIVERED", "CANCELLED"]}
    }
}});

db.drivers.createIndex({driverId: 1}, {unique: true});
db.drivers.createIndex({status: 1});
db.deliveries.createIndex({deliveryId: 1}, {unique: true});
db.deliveries.createIndex({orderId: 1}, {unique: true});
db.deliveries.createIndex({driverId: 1, status: 1});
