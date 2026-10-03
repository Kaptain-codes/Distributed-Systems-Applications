import ballerina/http;
import ballerina/sql;
import ballerina/uuid;

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

    resource function post .(http:Caller caller, http:Request req) returns error? {
    json body = check req.getJsonPayload();
    NewCustomer payload = check body.cloneWithType();

    string id = uuid:createType1AsString();
    _ = check customerDb->execute(`
        INSERT INTO customers (id, name, email, phone)
        VALUES (${id}, ${payload.name}, ${payload.email}, ${payload.phone})
    `);

    http:Response res = new;
    res.statusCode = 201;
    res.setJsonPayload({id, name: payload.name, email: payload.email, phone: payload.phone});
    check caller->respond(res);
}

    resource function get [string id](http:Caller caller) returns error? {
        Customer|sql:Error customer = check customerDb->queryRow(`
        SELECT id, name, email, phone FROM customers WHERE id = ${id}`);

        http:Response res = new;
        if customer is sql:Error {
            res.statusCode = 404;
            res.setJsonPayload({message: string `customer with id ${id} not found`});
        } else {
            res.statusCode = 200;
            res.setJsonPayload(customer);
        }
        check caller->respond(res);
    }
}
