import ballerinax/redis;
import ballerina/crypto;
import ballerina/uuid;

configurable string redisHost = "gateway-redis";
configurable int redisPort = 6379;
configurable string redisPassword = "";

redis:Client? idempotencyStore = ();

function redisAvailable() returns boolean {
    if idempotencyStore is redis:Client {
        return true;
    }

    redis:Client|error result = new (connection = {
        host: redisHost, port: redisPort, password: redisPassword
    });
    if result is redis:Client {
        idempotencyStore = result;
        return true;
    }
    return false;
}

function getRedisClient() returns redis:Client|error {
    if idempotencyStore is redis:Client {
        return <redis:Client>idempotencyStore;
    }
    return error("Redis is unavailable");
}

type IdempotencyEntry record {|
    int status;
    json body;
    string requestHash;
    string createdAt;
|};

function requestHash(string method, string path, string body) returns string {
    return crypto:hashSha256((method + path + body).toBytes()).toBase64();
}

function idempotencyKey(string serviceName, string method, string path, string key) returns string {
    return string `idempotency:${serviceName}:${method}:${path}:${key}`;
}

function validIdempotencyKey(string key) returns boolean {
    return uuid:validate(key);
}

function loadIdempotency(string key) returns IdempotencyEntry|error|() {
    if idempotencyStore is () {
        return ();
    }
    redis:Client store = check getRedisClient();
    string|redis:Error? storedResult = store->get(key);
    if storedResult is () {
        return ();
    }
    string|redis:Error stored = storedResult;
    if stored is redis:Error {
        return stored;
    }
    if stored.length() == 0 {
        return ();
    }
    json parsed = check stored.fromJsonString();
    return parsed.cloneWithType(IdempotencyEntry);
}

function reserveIdempotency(string key, string hash) returns boolean|error {
    if idempotencyStore is () {
        return error("Redis is unavailable");
    }
    redis:Client store = check getRedisClient();
    return store->setNxEx(key, {requestHash: hash, status: 0, body: {}, createdAt: "in-flight"}.toJsonString(), 86400);
}

function saveIdempotency(string key, int status, json body, string hash) returns error? {
    if idempotencyStore is () {
        return error("Redis is unavailable");
    }
    IdempotencyEntry entry = {status: status, body: body, requestHash: hash, createdAt: "UTC"};
    redis:Client store = check getRedisClient();
    string|redis:Error result = store->setEx(key, entry.toJsonString(), 86400);
    if result is redis:Error {
        return result;
    }
}


// The purpose of this file is to provide a simple idempotency mechanism for the API gateway. It uses Redis to store the results of requests that have been processed, allowing clients to safely retry requests without causing duplicate operations. The key functions include generating a unique request hash, validating idempotency keys, loading existing entries from Redis, reserving a new entry for in-flight requests, and saving completed request results.