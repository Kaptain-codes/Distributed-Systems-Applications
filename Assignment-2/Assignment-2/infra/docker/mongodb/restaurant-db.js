// restaurant-db: collections owned by the restaurant service, with validators and indexes.
// Runs once, when the container starts with an empty data volume.
db = db.getSiblingDB("food_delivery");

function ensureCollection(name, validator) {
    if (!db.getCollectionNames().includes(name)) {
        db.createCollection(name, {validator});
        return;
    }
    db.runCommand({collMod: name, validator});
}

ensureCollection("restaurants", {$jsonSchema: {
    bsonType: "object",
    required: ["restaurantId", "name", "address", "acceptingOrders", "openingHours", "menu"],
    properties: {
        restaurantId: {bsonType: "string"},
        acceptingOrders: {bsonType: "bool"},
        openingHours: {bsonType: "array"},
        menu: {bsonType: "array"}
    }
}});

db.restaurants.createIndex({restaurantId: 1}, {unique: true});
db.restaurants.createIndex({acceptingOrders: 1});
