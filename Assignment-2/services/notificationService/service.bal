import ballerina/http;

# A service representing a network-accessible API
# bound to port `9090`.
service /notification on new http:Listener(9090) {

    resource function get health() returns json {
        return {status: "UP", 'service: "notification"};
    }

}
