import ballerinax/mongodb;
import ballerinax/redis;
import ballerina/log;

configurable boolean durableStateEnabled = false;
configurable string mongoUri = "mongodb://localhost:27017/notifications";
configurable string mongoDatabase = "notifications";
configurable string redisHost = "notification-redis";
configurable int redisPort = 6379;

mongodb:Collection|error notificationsCollection = error("MongoDB is not initialized");
redis:Client? notificationRedisClient = ();

function initializeNotificationRedisClient() {
    if notificationRedisClient is redis:Client {
        return;
    }
    redis:Client|error result = new (connection = {host: redisHost, port: redisPort});
    if result is redis:Client {
        notificationRedisClient = result;
        return;
    }
    log:printWarn("Notification Redis is unavailable; continuing without Redis", 'error = result);
}

type NotificationDocument record {| anydata...; |};

class MongoNotificationRepository {
    *NotificationRepository;

    public function save(Notification item) returns error? {
        mongodb:Collection collection = check notificationsCollection;
        json document = item.toJson();
        if document is map<json> {
            _ = check collection->updateOne({id: item.id}, {set: document}, {upsert: true});
        }
    }

    public function getAll() returns map<Notification>|error {
        return findNotifications({});
    }

    public function getForRecipient(string recipientId) returns Notification[]|error {
        map<Notification>|error found = findNotifications({recipientId: recipientId});
        if found is error {
            return found;
        }
        Notification[] result = [];
        foreach Notification item in found {
            result.push(item);
        }
        return result;
    }

    public function getById(string id) returns Notification|error? {
        mongodb:Collection collection = check notificationsCollection;
        NotificationDocument|error? result = collection->findOne({id: id});
        if result is error || result is () {
            return result is error ? result : ();
        }
        return notificationFromDocument(result.toJson());
    }
}

NotificationRepository notificationRepository = new InMemoryNotificationRepository();

function initNotificationPersistence() returns error? {
    if !durableStateEnabled {
        return;
    }
    mongodb:Client mongoConnection = check new ({connection: mongoUri});
    mongodb:Database database = check mongoConnection->getDatabase(mongoDatabase);
    notificationsCollection = check database->getCollection("notifications");
    notificationRepository = new MongoNotificationRepository();
}

function findNotifications(map<json> query) returns map<Notification>|error {
    mongodb:Collection collection = check notificationsCollection;
    stream<NotificationDocument, error?> result = check collection->find(query);
    map<Notification> notificationsList = {};
    while true {
        record {| NotificationDocument value; |}|error? next = result.next();
        if next is error {
            return next;
        }
        if next is () {
            break;
        }
        Notification|error notification = notificationFromDocument(next.value.toJson());
        if notification is error {
            return notification;
        }
        notificationsList[notification.id] = notification;
    }
    return notificationsList;
}

function notificationFromDocument(json document) returns Notification|error {
    if document is map<json> && document.hasKey("_id") {
        _ = document.remove("_id");
    }
    return document.cloneWithType(Notification);
}
