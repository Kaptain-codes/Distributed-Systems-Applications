import ballerinax/mongodb;

// MongoDB is the only database. The in-memory backend exists so unit tests run without one.
public enum DatabaseBackend {
    MEMORY = "memory",
    MONGODB = "mongodb"
}

configurable DatabaseBackend databaseBackend = MEMORY;
configurable string mongodbConnectionUri = "mongodb://localhost:27017";
configurable string mongodbDatabase = "food_delivery";

// The MongoDB client is only created when MongoDB is the selected backend.
final mongodb:Client? mongoClient = databaseBackend == MONGODB
    ? checkpanic new ({connection: mongodbConnectionUri})
    : ();

isolated function configuredMongoCollection(string collectionName)
        returns mongodb:Collection|error {
    mongodb:Client? configuredClient = mongoClient;
    if configuredClient is () {
        return error("MongoDB is not the configured persistence backend");
    }
    mongodb:Database database = check configuredClient->getDatabase(mongodbDatabase);
    return database->getCollection(collectionName);
}
