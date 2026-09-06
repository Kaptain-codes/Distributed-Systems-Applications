import ballerina/http;

# A service representing a network-accessible API
# bound to port `9090`.
# NOTE: 'order' is a reserved word in Ballerina (used in query expressions'
# order by clause) — escaped with a leading ' to use it as an identifier.
service /'order on new http:Listener(9090) {

    resource function get health() returns json {
        return {status: "UP", 'service: "order"};
    }

}
