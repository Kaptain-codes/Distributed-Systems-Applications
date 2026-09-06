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
    resource function get orders/[string id]() returns json|error {
        return orderClient->get(string `/order/${id}`);
    }

    resource function get customer/[string id]() returns json|error {
        return customerClient->get(string `/customer/${id}`);
    }

    resource function get notifications/[string id]() returns json|error {
        return notificationClient->get(string `/notification/${id}`);
    }

    resource function get payments/[string id]() returns json|error {
        return paymentClient->get(string `/payment/${id}`);
    }

    resource function get admin/[string id]() returns json|error {
        return adminClient->get(string `/admin/${id}`);
    }

    resource function get delivery/[string id]() returns json|error {
        return deliveryClient->get(string `/delivery/${id}`);
    }

    resource function get restaurant/[string id]() returns json|error {
        return restaurantClient->get(string `/restaurant/${id}`);
    }
}
