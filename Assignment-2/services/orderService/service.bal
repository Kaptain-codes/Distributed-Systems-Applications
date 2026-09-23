import ballerina/http;
// import ballerinax/kafka;

# A service representing a network-accessible API
# bound to port `9090`.
# NOTE: 'order' is a reserved word in Ballerina (used in query expressions'
# order by clause) — escaped with a leading ' to use it as an identifier.
service /'order on new http:Listener(9090) {

    resource function get health() returns json {
        return {status: "UP", 'service: "order"};
     }
    // resource function get orders() returns json {
    //     kafka:Consumer kafkaConsumer = new({
    //         bootstrapServers: "localhost:9092",
    //         groupId: "order-service-group",
    //         topics: ["orders"]
    //     });
    //     json[] orders = [];
    //     var result = kafkaConsumer->poll();
    //     if (result is kafka:ConsumerRecord[]) {
    //         foreach var record in result {
    //             orders.push(record.value);  
    //         }
    //     }
    //     return {orders: orders};
    // }

    // resource function post orders(http:Caller caller, http:Request req) returns error? {
    //     json 'order = check req.getJsonPayload();
    //     kafka:Producer kafkaProducer = new({
    //         bootstrapServers: "localhost:9092"
    //     });
    //     var result = kafkaProducer->send({
    //         topic: "orders",
    //         value: 'order
    //     });
    //     if (result is kafka:Error) {
    //         return caller->respond("Failed to send order to Kafka");
    //     }
    //     return caller->respond("Order sent to Kafka successfully");
    // }

}
