// admin-db: collections owned by the admin service, with validators and indexes.
// Runs once, when the container starts with an empty data volume.
db = db.getSiblingDB("food_delivery");

function ensureCollection(name, validator) {
    if (!db.getCollectionNames().includes(name)) {
        db.createCollection(name, {validator});
        return;
    }
    db.runCommand({collMod: name, validator});
}

ensureCollection("restaurant_statistics", {$jsonSchema: {
    bsonType: "object",
    required: ["restaurantId", "restaurantName", "totalOrders", "completedOrders", "cancelledOrders", "grossRevenue"]
}});

ensureCollection("delivery_performance", {$jsonSchema: {
    bsonType: "object",
    required: ["driverId", "driverName", "assignedDeliveries", "completedDeliveries", "averageDeliveryMinutes"]
}});

db.restaurant_statistics.createIndex({restaurantId: 1}, {unique: true});
db.delivery_performance.createIndex({driverId: 1}, {unique: true});
