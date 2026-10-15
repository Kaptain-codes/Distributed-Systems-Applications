import ballerinax/mongodb;

public isolated function listCustomers() returns Customer[]|error {
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("customers");
        stream<Customer, error?> customerStream = check collection->find({}, targetType = Customer);
        return from Customer customer in customerStream
            select customer;
    }
    return memoryListCustomers();
}

public isolated function findCustomer(string customerId) returns Customer?|error {
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("customers");
        return collection->findOne({customerId}, targetType = Customer);
    }
    return memoryFindCustomer(customerId);
}

public isolated function createCustomer(Customer customer) returns Customer|error {
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("customers");
        Customer? existing = check collection->findOne(
            {"$or": [{customerId: customer.customerId}, {email: customer.email}]}, targetType = Customer);
        if existing is Customer {
            return error("Customer identifier or email is already registered");
        }
        check collection->insertOne(customer);
        return customer;
    }
    return memoryCreateCustomer(customer);
}

public isolated function updateCustomer(string customerId, CustomerUpdate update)
        returns Customer|error {
    Customer? customer = check findCustomer(customerId);
    if customer is () {
        return error(string `Customer '${customerId}' was not found`);
    }
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("customers");
        Customer? emailOwner = check collection->findOne({email: update.email}, targetType = Customer);
        if emailOwner is Customer && emailOwner.customerId != customerId {
            return error(string `Email '${update.email}' is already registered`);
        }
        _ = check collection->updateOne({customerId}, {
            set: {
                fullName: update.fullName,
                email: update.email,
                phoneNumber: update.phoneNumber
            }
        });
    } else {
        return memoryUpdateCustomer(customerId, update);
    }
    Customer? updated = check findCustomer(customerId);
    return updated is Customer ? updated : error(string `Customer '${customerId}' was not found`);
}

public isolated function addDeliveryAddress(string customerId, DeliveryAddress address)
        returns DeliveryAddress|error {
    Customer? customer = check findCustomer(customerId);
    if customer is () {
        return error(string `Customer '${customerId}' was not found`);
    }
    if customer.addresses.indexOf(address) is int {
        return error(string `Address '${address.addressId}' already exists`);
    }
    foreach DeliveryAddress existingAddress in customer.addresses {
        if existingAddress.addressId == address.addressId {
            return error(string `Address '${address.addressId}' already exists`);
        }
    }
    if databaseBackend == MONGODB {
        customer.addresses.push(address.clone());
        mongodb:Collection collection = check configuredMongoCollection("customers");
        _ = check collection->updateOne({customerId}, {set: {addresses: customer.addresses}});
    } else {
        return memoryAddDeliveryAddress(customerId, address);
    }
    return address;
}

public isolated function recordHistoricalOrder(string customerId, string orderId)
        returns Customer|error {
    Customer? customer = check findCustomer(customerId);
    if customer is () {
        return error(string `Customer '${customerId}' was not found`);
    }
    if customer.historicalOrderIds.indexOf(orderId) is () {
        customer.historicalOrderIds.push(orderId);
        if databaseBackend == MONGODB {
            mongodb:Collection collection = check configuredMongoCollection("customers");
            _ = check collection->updateOne({customerId},
                {set: {historicalOrderIds: customer.historicalOrderIds}});
        } else {
            return memoryRecordHistoricalOrder(customerId, orderId);
        }
    }
    Customer? updated = check findCustomer(customerId);
    return updated is Customer ? updated : error(string `Customer '${customerId}' was not found`);
}

