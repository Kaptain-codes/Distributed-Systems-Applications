import ballerina/http;

configurable int servicePort = 9101;

isolated function customerNotFound(string message) returns NotFoundResponse =>
    {body: {message}};

isolated function customerConflict(string message) returns ConflictResponse =>
    {body: {message}};

// Manages customer profiles, delivery addresses, and order history.
service /customers on new http:Listener(servicePort) {
    // Provides a lightweight readiness signal for container orchestration.
    isolated resource function get health() returns map<string> =>
        {status: "UP", component: "customer_service"};

    // Lists all registered customers.
    isolated resource function get .() returns Customer[]|error => listCustomers();

    // Registers a new customer.
    isolated resource function post .(Customer customer) returns Customer|ConflictResponse {
        Customer|error result = createCustomer(customer);
        return result is error ? customerConflict(result.message()) : result;
    }

    // Returns one customer by identifier.
    isolated resource function get [string customerId]() returns Customer|NotFoundResponse|error {
        Customer? customer = check findCustomer(customerId);
        return customer is Customer ? customer :
            customerNotFound(string `Customer '${customerId}' was not found`);
    }

    // Replaces the mutable profile fields of a customer.
    isolated resource function put [string customerId](CustomerUpdate update)
            returns Customer|NotFoundResponse|ConflictResponse {
        Customer|error result = updateCustomer(customerId, update);
        if result is Customer {
            return result;
        }
        return result.message().includes("not found") ? customerNotFound(result.message()) :
            customerConflict(result.message());
    }

    // Adds a delivery address to a customer account.
    isolated resource function post [string customerId]/addresses(DeliveryAddress address)
            returns DeliveryAddress|NotFoundResponse|ConflictResponse {
        DeliveryAddress|error result = addDeliveryAddress(customerId, address);
        if result is DeliveryAddress {
            return result;
        }
        return result.message().includes("not found") ? customerNotFound(result.message()) :
            customerConflict(result.message());
    }

    // Records an order in customer history. Kafka will trigger this flow later.
    isolated resource function post [string customerId]/orders/[string orderId]()
            returns Customer|NotFoundResponse {
        Customer|error result = recordHistoricalOrder(customerId, orderId);
        return result is error ? customerNotFound(result.message()) : result;
    }
}

