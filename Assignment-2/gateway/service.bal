import ballerina/http;

// API Gateway - single REST entry point for the service APIs.

configurable int port = 8080;

// These resolve via Docker's internal DNS on the `backbone` network — the
// service name IS the hostname, and 9090 is what every service actually
// listens on internally (host-side 8081-8087 mappings are only for
// reaching them from outside Docker, e.g. from your own machine).
configurable string orderService = "http://order-service:9090";
configurable string customerService = "http://customer-service:9090";
configurable string notificationService = "http://notification-service:9090";
configurable string paymentService = "http://payment-service:9090";
configurable string adminService = "http://admin-service:9090";
configurable string deliveryService = "http://delivery-service:9090";
configurable string restaurantService = "http://restaurant-service:9090";

final http:Client orderClient = check new (orderService);
final http:Client customerClient = check new (customerService);
final http:Client notificationClient = check new (notificationService);
final http:Client paymentClient = check new (paymentService);
final http:Client adminClient = check new (adminService);
final http:Client deliveryClient = check new (deliveryService);
final http:Client restaurantClient = check new (restaurantService);

service /api on new http:Listener(port) {

    resource function get health() returns json {
        return {status: "UP", 'service: "gateway"};
    }

    // These resources functions are used for reverse proxying the requests to the respective services. 
    // The path of the request is used to determine which service to forward the request to.
    resource function get orders/[string id]() returns json|http:Response {
        json|error result = orderClient->get(string `/order/${id}`);
        if result is error {
            return unavailableResponse(result);
        }
        return result;
    }

    resource function get customer/[string id]() returns json|http:Response {
        json|error result = customerClient->get(string `/customer/${id}`);
        if result is error {
            return unavailableResponse(result);
        }
        return result;
    }

    resource function get notifications/[string id]() returns json|http:Response {
        json|error result = notificationClient->get(string `/notification/${id}`);
        if result is error {
            return unavailableResponse(result);
        }
        return result;
    }

    resource function get payments/[string id]() returns json|http:Response {
        json|error result = paymentClient->get(string `/payment/${id}`);
        if result is error {
            return unavailableResponse(result);
        }
        return result;
    }

    resource function get admin/[string id]() returns json|http:Response {
        json|error result = adminClient->get(string `/admin/${id}`);
        if result is error {
            return unavailableResponse(result);
        }
        return result;
    }

    resource function get delivery/[string id]() returns json|http:Response {
        json|error result = deliveryClient->get(string `/delivery/${id}`);
        if result is error {
            return unavailableResponse(result);
        }
        return result;
    }

    resource function get restaurant/[string id]() returns json|http:Response {
        json|error result = restaurantClient->get(string `/restaurant/${id}`);
        if result is error {
            return unavailableResponse(result);
        }
        return result;
    }
}

function unavailableResponse(error _err) returns http:Response {
    http:Response response = new;
    response.statusCode = 503;
    response.setJsonPayload({status: "DOWN", message: "downstream service unavailable"});
    return response;
}
