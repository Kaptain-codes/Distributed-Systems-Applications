import ballerinax/mongodb;
import ballerina/log;
import ballerina/task;
import ballerina/time;
import ballerina/uuid;

// MongoDB is enabled only by the Docker runtime. Unit tests keep the existing
// in-memory mode so they do not require infrastructure.
configurable boolean durableStateEnabled = false;
configurable string mongoUri = "mongodb://localhost:27017/orders";
configurable int mongoSocketTimeoutMs = 3000;
configurable int mongoConnectionTimeoutMs = 3000;

mongodb:Collection|error ordersCollection = error("MongoDB is not initialized");
mongodb:Collection|error processedEventsCollection = error("MongoDB is not initialized");
mongodb:Collection|error pendingEventsCollection = error("MongoDB is not initialized");
mongodb:Collection|error outboxCollection = error("MongoDB is not initialized");

type DurableEvent record {|
    string eventId;
    string orderId;
    string rawPayload;
    string topic;
    int partition;
    int offset;
    string status = "PROCESSING";
    string updatedAt;
|};

type PendingKafkaOffset record {|
    string topic;
    int partition;
    int offset;
|};

map<PendingKafkaOffset> pendingKafkaOffsets = {};

type MongoDocument record {| anydata...; |};

type AtomicTransitionResult record {|
    Order orderValue;
    boolean stale = false;
|};

function initDurableState() returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Client|error mongoConnection = new ({
        connection: mongoUri,
        options: {
            socketTimeout: mongoSocketTimeoutMs,
            connectionTimeout: mongoConnectionTimeoutMs
        }
    });
    if mongoConnection is error {
        return mongoConnection;
    }
    mongodb:Database|error database = check mongoConnection->getDatabase("orders");
    mongodb:Database databaseValue = check database;
    ordersCollection = check databaseValue->getCollection("orders");
    processedEventsCollection = check databaseValue->getCollection("processed_events");
    pendingEventsCollection = check databaseValue->getCollection("pending_events");
    outboxCollection = check databaseValue->getCollection("outbox");
    mongodb:Collection orders = check ordersCollection;
    mongodb:Collection processed = check processedEventsCollection;
    mongodb:Collection pending = check pendingEventsCollection;
    mongodb:Collection outbox = check outboxCollection;
    check ensureUniqueIndex(orders, {orderId: 1}, "orderId_unique", "orderId_1");
    check ensureUniqueIndex(processed, {eventId: 1}, "eventId_unique", "eventId_1");
    check ensureUniqueIndex(pending, {eventId: 1}, "eventId_unique", "eventId_1");
    check ensureUniqueIndex(outbox, {eventId: 1}, "eventId_unique", "eventId_1");
    check ensureIndex(processed, {status: 1}, "status_index");
    check ensureIndex(outbox, {status: 1}, "status_index");
    check recoverDurableWork();
    check recoverDurableOutbox();
}

function ensureIndex(mongodb:Collection collection, map<json> keys, string name) returns error? {
    error? dropped = collection->dropIndex(name);
    check collection->createIndex(keys, {name: name});
}

function ensureUniqueIndex(mongodb:Collection collection, map<json> keys,
        string name, string legacyName) returns error? {
    // Reconcile both known names so restarts work with either a fresh volume,
    // an older non-unique index, or a volume already migrated by this code.
    // A missing index is expected during this idempotent migration.
    error? droppedCurrent = collection->dropIndex(name);
    if legacyName != name {
        error? droppedLegacy = collection->dropIndex(legacyName);
    }
    check collection->createIndex(keys, {unique: true, name: name});
}

function recoverDurableWork() returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Collection processed = check processedEventsCollection;
    stream<record {| anydata...; |}, error?>|mongodb:Error result =
        processed->find({status: "PROCESSING"});
    if result is mongodb:Error {
        return result;
    }
    stream<record {| anydata...; |}, error?> records = result;
    while true {
        record {| record {| anydata...; |} value; |}|error? next = records.next();
        if next is () {
            break;
        }
        if next is error {
            return next;
        }
        record {| anydata...; |} document = next.value;
        json value = document.toJson();
        if value is map<json> && value["eventId"] is string &&
            value["orderId"] is string && value["rawPayload"] is string {
            string eventId = <string>value["eventId"];
            string orderId = <string>value["orderId"];
            if value["topic"] is string && value["partition"] is int &&
                value["offset"] is int {
                pendingKafkaOffsets[eventId] = {
                    topic: <string>value["topic"],
                    partition: <int>value["partition"],
                    offset: <int>value["offset"]
                };
            }
            json|error raw = (<string>value["rawPayload"]).fromJsonString();
            if raw is json {
                json[] pending = pendingEvents[orderId] ?: [];
                pending.push(raw);
                pendingEvents[orderId] = pending;
            }
        }
    }
}

class DurableRecoveryJob {
    *task:Job;

    public function execute() {
        foreach string orderId in pendingEvents.keys() {
            replayPendingEvents(orderId);
        }
        republishDurableOutbox();
    }
}

function recoverDurableOutbox() returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Collection collection = check outboxCollection;
    stream<record {| anydata...; |}, error?>|mongodb:Error result =
        collection->find({status: "PENDING"});
    if result is mongodb:Error {
        return result;
    }
    stream<record {| anydata...; |}, error?> records = result;
    while true {
        record {| record {| anydata...; |} value; |}|error? next = records.next();
        if next is () {
            break;
        }
        if next is error {
            return next;
        }
        json document = next.value.toJson();
        if document is map<json> {
            json? topic = document["topic"];
            json? orderId = document["orderId"];
            json? payload = document["payload"];
            if topic is string && orderId is string && payload is json {
                error? published = publishOrderEventInternal(topic, orderId, payload, false, false);
                if published is error {
                    log:printError("durable outbox republish failed", 'error = published);
                } else if payload is map<json> && payload["eventId"] is string {
                    error? marked = markDurableOutboxPublished(<string>payload["eventId"]);
                    if marked is error {
                        log:printError("durable outbox status update failed", 'error = marked);
                    }
                }
            }
        }
    }
}

function republishDurableOutbox() {
    error? recovered = recoverDurableOutbox();
    if recovered is error {
        log:printError("durable outbox recovery failed", 'error = recovered);
    }
}

// The connector does not expose collection transactions in this version.
// State and the outbox are therefore written before publication, while the
// publisher remains at-least-once and uses event IDs for downstream dedupe.
function persistOrderSnapshot(Order orderValue, json[] events = []) returns error? {
    if !durableStateEnabled {
        return;
    }

    mongodb:Collection collection = check ordersCollection;
    json document = orderValue.toJson();
    if document is map<json> {
        document["orderId"] = orderValue.orderId;
        document["outbox"] = events;
        mongodb:Update update = {set: document};
        _ = check collection->updateOne({orderId: orderValue.orderId}, update, {upsert: true});
    }
}

function applyAtomicTransition(Order current, Order proposed) returns Order|error {
    json[] history = current.statusHistory;
    if proposed.status != current.status {
        history.push({status: proposed.status, changedAt: proposed.updatedAt});
    }
    proposed.statusHistory = history;
    if !durableStateEnabled {
        return proposed;
    }
    mongodb:Collection collection = check ordersCollection;
    json document = proposed.toJson();
    if !(document is map<json>) {
        return error("order transition could not be serialized");
    }
    _ = document.remove("orderId");
    _ = document.remove("statusHistory");
    map<json> updateDocument = {"set": document};
    if proposed.status != current.status {
        updateDocument["push"] = {
            statusHistory: {status: proposed.status, changedAt: proposed.updatedAt}
        };
    }
    mongodb:Update|error updateResult = updateDocument.cloneWithType(mongodb:Update);
    if updateResult is error {
        return updateResult;
    }
    mongodb:UpdateResult result = check collection->updateOne(
        {orderId: current.orderId, status: current.status, version: current.version},
        updateResult);
    if result.matchedCount == 0 {
        log:printWarn("stale order transition rejected orderId=" + current.orderId +
            " expectedStatus=" + current.status +
            " expectedVersion=" + current.version.toString());
        return error("STALE_TRANSITION");
    }
    MongoDocument|error? refreshed = collection->findOne({orderId: current.orderId});
    if refreshed is MongoDocument {
        return restoreMongoOrder(refreshed.toJson());
    }
    if refreshed is error {
        return refreshed;
    }
    return error("order transition result was not found");
}

function restoreMongoOrder(json restoredJson) returns Order|error {
    if !(restoredJson is map<json>) {
        return error("order transition result was not an object");
    }
    if restoredJson.hasKey("_id") {
        _ = restoredJson.remove("_id");
    }
    if restoredJson.hasKey("outbox") {
        _ = restoredJson.remove("outbox");
    }
    Order|error restored = restoredJson.cloneWithType(Order);
    if restored is error {
        return error("order transition result could not be decoded", restored);
    }
    return restored;
}

function derivedEventId(string sourceEventId, string eventType) returns string|error {
    string|error generated = uuid:createType5AsString(uuid:NAME_SPACE_URL,
        sourceEventId + ":" + eventType);
    if generated is error {
        return error("derived event ID generation failed", generated);
    }
    return generated;
}

function loadDurableOrders() returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Collection collection = check ordersCollection;
    stream<record {| anydata...; |}, error?>|mongodb:Error result =
        collection->find({});
    if result is mongodb:Error {
        return result;
    }
    stream<record {| anydata...; |}, error?> documents = result;
    while true {
        record {| record {| anydata...; |} value; |}|error? next = documents.next();
        if next is () {
            break;
        }
        if next is error {
            return next;
        }
        record {| anydata...; |} document = next.value;
        json orderJson = document.toJson();
        if orderJson is map<json> {
            if orderJson.hasKey("_id") {
                _ = orderJson.remove("_id");
            }
            if orderJson.hasKey("outbox") {
                _ = orderJson.remove("outbox");
            }
        }
        Order|error restored = orderJson.cloneWithType(Order);
        if restored is Order {
            orders[restored.orderId] = restored;
        } else {
            log:printError("durable order document could not be restored", 'error = restored);
        }
    }
}

// PROCESSING records are deliberately recoverable. A crash before the
// business write leaves the record eligible for replay after restart.
function claimDurableEvent(string eventId, string orderId, string rawPayload,
        string topic, int partition, int offset) returns boolean|error {
    if !durableStateEnabled {
        return true;
    }
    mongodb:Collection collection = check processedEventsCollection;
    DurableEvent marker = {
        eventId: eventId,
        orderId: orderId,
        rawPayload: rawPayload,
        topic: topic,
        partition: partition,
        offset: offset,
        status: "PROCESSING",
        updatedAt: time:utcToString(time:utcNow())
    };
    error? inserted = collection->insertOne(marker);
    if inserted is () {
        return true;
    }
    mongodb:Error|error duplicateLookup = inserted;
    MongoDocument|error? existing = collection->findOne({eventId: eventId});
    if existing is MongoDocument {
        return false;
    }
    return duplicateLookup;
}

function completeDurableEvent(string eventId) returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Collection collection = check processedEventsCollection;
    _ = check collection->updateOne({eventId: eventId},
        {set: {status: "COMPLETED", updatedAt: time:utcToString(time:utcNow())}});
}

function isDurableEventCompleted(string eventId) returns boolean|error {
    if !durableStateEnabled {
        return true;
    }
    mongodb:Collection collection = check processedEventsCollection;
    MongoDocument|error? existing = collection->findOne({eventId: eventId});
    if existing is error {
        return existing;
    }
    if existing is () {
        return false;
    }
    json document = existing.toJson();
    if document is map<json> && document["status"] is string {
        return <string>document["status"] == "COMPLETED";
    }
    return false;
}

function persistDurablePendingEvent(string eventId, string orderId, string rawPayload) returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Collection collection = check pendingEventsCollection;
    error? inserted = collection->insertOne({
        "eventId": eventId,
        "orderId": orderId,
        "rawPayload": rawPayload,
        "updatedAt": time:utcToString(time:utcNow())
    });
    if inserted is error {
        MongoDocument|error? existing = collection->findOne({eventId: eventId});
        if existing is MongoDocument {
            return;
        }
        return inserted;
    }
}

function removeDurablePendingEvent(string eventId) returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Collection collection = check pendingEventsCollection;
    _ = check collection->deleteOne({eventId: eventId});
}

function addDurableOutbox(string eventId, string topic, string orderId, json payload) returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Collection collection = check outboxCollection;
    _ = check collection->updateOne({eventId: eventId},
        {set: {eventId: eventId, topic: topic, orderId: orderId, payload: payload,
            status: "PENDING", updatedAt: time:utcToString(time:utcNow())}},
        {upsert: true});
}

function markDurableOutboxPublished(string eventId) returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Collection collection = check outboxCollection;
    _ = check collection->updateOne({eventId: eventId},
        {set: {status: "PUBLISHED", updatedAt: time:utcToString(time:utcNow())}});
}

// how is the mongo client used here? It is used to connect to the MongoDB database and perform various operations such as inserting, updating, and querying documents in different collections. The client is initialized with a connection URI and options for socket and connection timeouts. Once connected, it retrieves specific collections (orders, processed events, pending events, outbox) and performs operations like ensuring indexes, recovering durable work, persisting order snapshots, applying atomic transitions, and managing durable events and outbox messages.