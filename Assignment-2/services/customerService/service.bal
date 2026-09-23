import ballerina/http;

// configurable string orderService = "http://order-service:9090";
// http:Client orderClient = new (orderService);

# A service representing a network-accessible API
# bound to port `9090`.
service /customer on new http:Listener(9090) {

    resource function get health() returns json {
        return {status: "UP", 'service: "customer"};
    }
    // resource function get orders() returns http:Ok {
    //     orderClient->get
    // }

}
