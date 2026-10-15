// customer-db: collections owned by the customer service, with validators and indexes.
// Runs once, when the container starts with an empty data volume.
db = db.getSiblingDB("food_delivery");

function ensureCollection(name, validator) {
    if (!db.getCollectionNames().includes(name)) {
        db.createCollection(name, {validator});
        return;
    }
    db.runCommand({collMod: name, validator});
}

ensureCollection("customers", {$jsonSchema: {
    bsonType: "object",
    required: ["customerId", "fullName", "email", "phoneNumber", "addresses", "historicalOrderIds"],
    properties: {
        customerId: {bsonType: "string"},
        email: {bsonType: "string"},
        addresses: {bsonType: "array"},
        historicalOrderIds: {bsonType: "array"}
    }
}});

db.customers.createIndex({customerId: 1}, {unique: true});
db.customers.createIndex({email: 1}, {unique: true});
