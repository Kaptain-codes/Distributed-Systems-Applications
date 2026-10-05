// DLQ record storage.
//
// With `durableStateEnabled` (set in Docker Compose), records go to the MongoDB
// collection `admin.dlq_log`. Without it, every function here does nothing
// and `GET /admin/dlq` returns the in-memory `dlq` map.

import ballerina/time;
import ballerinax/mongodb;

configurable boolean durableStateEnabled = false;
configurable string mongoUri = "mongodb://localhost:27017/admin";

const string DATABASE_NAME = "admin";
const string DLQ_COLLECTION = "dlq_log";

// One document per Kafka location (topic, partition, offset), so a redelivered
// record is stored once.
const string LOCATION_INDEX = "dlq_location_unique";
// Lookup index for replay; not unique, because one event can fail in several consumers.
const string EVENT_ID_INDEX = "eventId_index";
// Name used by an earlier version; dropped on startup.
const string LEGACY_EVENT_ID_INDEX = "eventId_unique";

const string STATUS_REPLAYED = "REPLAYED";

// A stored DLQ record.
type DlqDocument record {|
    string dlqTopic;
    int dlqPartition;
    int dlqOffset;
    string originalTopic;
    string key;
    string? eventId = ();
    string consumerGroup;
    string rawPayload;
    string 'error;
    int attempts;
    string receivedAt;
    string status = "PARKED";
    string? replayedAt = ();
|};

type MongoDocument record {|
    anydata...;
|};

// In-memory record shape used when durable state is off.
type DlqRecord record {|
    string topic;
    string rawPayload;
    string 'error;
    int attempts;
    string receivedAt;
|};

// In-memory fallback returned by `GET /admin/dlq` when durable state is off.
map<DlqRecord> dlq = {};

mongodb:Collection|error dlqCollection = error("MongoDB is not initialized");

// Connects to MongoDB and rebuilds the `dlq_log` indexes. Runs once at startup.
function initDurableState() returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Client|error mongoConnection = new ({connection: mongoUri});
    if mongoConnection is error {
        return mongoConnection;
    }
    mongodb:Database database = check mongoConnection->getDatabase(DATABASE_NAME);
    dlqCollection = check database->getCollection(DLQ_COLLECTION);
    mongodb:Collection collection = check dlqCollection;

    // Drop and recreate so a volume from any earlier version ends up with the same indexes.
    dropIndexIfPresent(collection, LOCATION_INDEX);
    dropIndexIfPresent(collection, LEGACY_EVENT_ID_INDEX);
    check collection->createIndex({dlqTopic: 1, dlqPartition: 1, dlqOffset: 1},
        {unique: true, name: LOCATION_INDEX});
    dropIndexIfPresent(collection, EVENT_ID_INDEX);
    check collection->createIndex({eventId: 1}, {name: EVENT_ID_INDEX});
}

// Drops an index; a missing index is expected and ignored.
function dropIndexIfPresent(mongodb:Collection collection, string indexName) {
    mongodb:Error? dropped = collection->dropIndex(indexName);
    if dropped is mongodb:Error {
        // Nothing to do: the index did not exist yet.
    }
}

// Inserts a DLQ document. A duplicate at the same location counts as success.
function persistDlq(DlqDocument document) returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Collection collection = check dlqCollection;
    error? inserted = collection->insertOne(document);
    if inserted is () {
        return;
    }
    MongoDocument|error? existing = collection->findOne({
        dlqTopic: document.dlqTopic,
        dlqPartition: document.dlqPartition,
        dlqOffset: document.dlqOffset
    });
    if existing is () || existing is error {
        return inserted;
    }
}

// Returns every stored DLQ document.
function listDurableDlq() returns json[]|error {
    if !durableStateEnabled {
        return [];
    }
    mongodb:Collection collection = check dlqCollection;
    stream<record {|anydata...;|}, error?>|mongodb:Error result = collection->find({});
    if result is mongodb:Error {
        return result;
    }
    json[] entries = [];
    stream<record {|anydata...;|}, error?> records = result;
    while true {
        record {|record {|anydata...;|} value;|}|error? next = records.next();
        if next is () {
            break;
        }
        if next is error {
            return next;
        }
        entries.push(next.value.toJson());
    }
    return entries;
}

// True when the event was already replayed to this topic.
function isReplayCompleted(string originalTopic, string eventId) returns boolean|error {
    if !durableStateEnabled {
        return false;
    }
    mongodb:Collection collection = check dlqCollection;
    MongoDocument|error? found = collection->findOne({originalTopic: originalTopic, eventId: eventId});
    if found is error {
        return found;
    }
    if found is () {
        return false;
    }
    json value = found.toJson();
    return value is map<json> && value["status"] == STATUS_REPLAYED;
}

// Makes sure a `dlq_log` row exists for a replay. Inserts a PARKED row
// only if none exists yet; an existing row is left untouched.
function ensureDlqReplayRecord(string originalTopic, string eventId, string key, string rawPayload) returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Collection collection = check dlqCollection;
    _ = check collection->updateOne({originalTopic: originalTopic, eventId: eventId},
        {
        setOnInsert: {
            eventId: eventId,
            originalTopic: originalTopic,
            key: key,
            rawPayload: rawPayload,
            'error: "REPLAY_REQUESTED",
            attempts: 0,
            receivedAt: time:utcToString(time:utcNow()),
            status: "PARKED"
        }
    },
        {upsert: true});
}

// Marks the (topic, eventId) row as REPLAYED and stamps `replayedAt`.
function markDlqReplayed(string originalTopic, string eventId) returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Collection collection = check dlqCollection;
    _ = check collection->updateOne({originalTopic: originalTopic, eventId: eventId},
        {set: {status: STATUS_REPLAYED, replayedAt: time:utcToString(time:utcNow())}});
}

// Pulls a string `eventId` out of a parsed payload; `()` if there is none.
function extractEventId(json|error payload) returns string? {
    if payload is map<json> && payload["eventId"] is string {
        return <string>payload["eventId"];
    }
    return ();
}

// A stable text key for one Kafka location.
function dlqLocationKey(string topic, int partition, int offset) returns string {
    return string `${topic}:${partition}:${offset}`;
}
