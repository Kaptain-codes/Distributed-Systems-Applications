import ballerina/http;

configurable string baseUrl = "http://localhost:9090/api";
configurable int pollMs = 2000;
configurable boolean autoRegister = true;
configurable boolean idempotencyEnabled = false;
configurable boolean kafkaEnabled = false;
configurable string kafkaBootstrapServers = "localhost:29092";
configurable string kafkaGroupId = "client-debug";
configurable string[] kafkaTopics = ["orders.created", "orders.confirmed", "orders.preparing",
    "orders.ready", "delivery.assigned", "delivery.picked_up", "delivery.completed",
    "orders.delivered", "orders.cancelled"];
configurable int httpTimeoutSeconds = 3;
configurable int httpRetries = 1;

final http:Client apiClient = check new (baseUrl, {
    timeout: <decimal>httpTimeoutSeconds
});
