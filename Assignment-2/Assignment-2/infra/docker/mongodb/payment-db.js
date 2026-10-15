// payment-db: collections owned by the payment service, with validators and indexes.
// Runs once, when the container starts with an empty data volume.
db = db.getSiblingDB("food_delivery");

function ensureCollection(name, validator) {
    if (!db.getCollectionNames().includes(name)) {
        db.createCollection(name, {validator});
        return;
    }
    db.runCommand({collMod: name, validator});
}

ensureCollection("payments", {$jsonSchema: {
    bsonType: "object",
    required: ["paymentId", "orderId", "customerId", "amount", "currency", "status"],
    properties: {
        paymentId: {bsonType: "string"},
        status: {enum: ["PENDING", "COMPLETED", "FAILED", "REFUNDED"]}
    }
}});

db.payments.createIndex({paymentId: 1}, {unique: true});
db.payments.createIndex({orderId: 1});
