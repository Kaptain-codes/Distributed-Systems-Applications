// Admin HTTP API: health, dead-letter queue (DLQ) visibility and replay, and reports.
//
// Reached through the gateway at /api/admin/... ; inside Docker the service
// listens on port 9090.

import ballerina/http;

configurable int port = 9090;

service /admin on new http:Listener(port) {

    function init() returns error? {
        check initDurableState();
        return startDlqConsumer();
    }

    resource function get health() returns json {
        return {status: "UP", 'service: "admin"};
    }

    // Every parked DLQ record: from MongoDB when durable state is on,
    // otherwise from the in-memory map.
    resource function get dlq() returns json|error {
        if durableStateEnabled {
            return check listDurableDlq();
        }
        return dlq.toJson();
    }

    // Re-sends a parked payload to its original topic (see `dlq_replay.bal`).
    // Replays run one at a time.
    resource function post dlq/replay(@http:Payload DlqReplayRequest request) returns json|error {
        lock {
            return replayDlqRecord(request);
        }
    }

    // Report endpoints. They currently return fixed placeholder values.

    resource function get reports/restaurants() returns json {
        return {restaurants: [], generatedAt: "UTC"};
    }

    resource function get reports/restaurants/[string restaurantId]() returns json {
        return {restaurantId: restaurantId, placed: 0, confirmed: 0, rejected: 0, cancelled: 0, delivered: 0};
    }

    resource function get reports/deliveries() returns json {
        return {deliveries: [], generatedAt: "UTC"};
    }
}
