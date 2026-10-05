import ballerinax/mongodb;
import ballerina/time;

configurable boolean durableStateEnabled = false;
configurable string mongoUri = "mongodb://localhost:27017/admin";

mongodb:Collection|error dlqCollection = error("MongoDB is not initialized");
type MongoDocument record {| anydata...; |};

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

function extractEventId(json|error payload) returns string? {
    if payload is map<json> && payload["eventId"] is string {
        return <string>payload["eventId"];
    }
    return ();
}

function dlqLocationKey(string topic, int partition, int offset) returns string {
    return string `${topic}:${partition}:${offset}`;
}

function initDurableState() returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Client|error mongoConnection = new ({connection: mongoUri});
    if mongoConnection is error {
        return mongoConnection;
    }
    mongodb:Database|error database = check mongoConnection->getDatabase("admin");
    mongodb:Database databaseValue = check database;
    dlqCollection = check databaseValue->getCollection("dlq_log");
    mongodb:Collection collection = check dlqCollection;
    error? dropped = collection->dropIndex("dlq_location_unique");
    error? droppedLegacy = collection->dropIndex("eventId_unique");
    check collection->createIndex({dlqTopic: 1, dlqPartition: 1, dlqOffset: 1},
        {unique: true, name: "dlq_location_unique"});
    error? droppedEventId = collection->dropIndex("eventId_index");
    check collection->createIndex({eventId: 1}, {name: "eventId_index"});
}

function persistDlq(DlqDocument document) returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Collection collection = check dlqCollection;
    error? inserted = collection->insertOne(document);
    if inserted is error {
        MongoDocument|error? existing = collection->findOne({
            dlqTopic: document.dlqTopic,
            dlqPartition: document.dlqPartition,
            dlqOffset: document.dlqOffset
        });
        if existing is () || existing is error {
            return inserted;
        }
    }
}

function listDurableDlq() returns json[]|error {
    if !durableStateEnabled {
        return [];
    }
    mongodb:Collection collection = check dlqCollection;
    stream<record {| anydata...; |}, error?>|mongodb:Error result = collection->find({});
    if result is mongodb:Error {
        return result;
    }
    json[] entries = [];
    stream<record {| anydata...; |}, error?> records = result;
    while true {
        record {| record {| anydata...; |} value; |}|error? next = records.next();
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
    return value is map<json> && value["status"] == "REPLAYED";
}

function ensureDlqReplayRecord(string originalTopic, string eventId, string key, string rawPayload) returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Collection collection = check dlqCollection;
    _ = check collection->updateOne({originalTopic: originalTopic, eventId: eventId},
        {setOnInsert: {
            eventId: eventId,
            originalTopic: originalTopic,
            key: key,
            rawPayload: rawPayload,
            'error: "REPLAY_REQUESTED",
            attempts: 0,
            receivedAt: time:utcToString(time:utcNow()),
            status: "PARKED"
        }},
        {upsert: true});
}

function markDlqReplayed(string originalTopic, string eventId) returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Collection collection = check dlqCollection;
    _ = check collection->updateOne({originalTopic: originalTopic, eventId: eventId},
        {set: {status: "REPLAYED", replayedAt: time:utcToString(time:utcNow())}});
}
