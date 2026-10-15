// This in-memory repository is used until database adapters are introduced.
isolated table<Customer> key(customerId) customerTable = table [];

// Returns snapshots of all registered customers.
isolated function memoryListCustomers() returns Customer[] {
    lock {
        return customerTable.toArray().clone();
    }
}

// Finds a customer without leaking mutable repository state.
isolated function memoryFindCustomer(string customerId) returns Customer? {
    lock {
        Customer? customer = customerTable[customerId];
        return customer is Customer ? customer.clone() : ();
    }
}

// Registers a customer when the identifier and email are unique.
isolated function memoryCreateCustomer(Customer customer) returns Customer|error {
    lock {
        Customer storedCustomer = customer.clone();
        if customerTable.hasKey(storedCustomer.customerId) {
            return error(string `Customer '${storedCustomer.customerId}' already exists`);
        }
        foreach Customer existingCustomer in customerTable {
            if existingCustomer.email == storedCustomer.email {
                return error(string `Email '${storedCustomer.email}' is already registered`);
            }
        }
        customerTable.add(storedCustomer);
        return storedCustomer.clone();
    }
}

// Updates profile details while preserving identity, addresses, and history.
isolated function memoryUpdateCustomer(string customerId, CustomerUpdate update)
        returns Customer|error {
    lock {
        Customer? customer = customerTable[customerId];
        if customer is () {
            return error(string `Customer '${customerId}' was not found`);
        }
        foreach Customer existingCustomer in customerTable {
            if existingCustomer.customerId != customerId && existingCustomer.email == update.email {
                return error(string `Email '${update.email}' is already registered`);
            }
        }
        customer.fullName = update.fullName;
        customer.email = update.email;
        customer.phoneNumber = update.phoneNumber;
        return customer.clone();
    }
}

// Adds a uniquely identified delivery address to a customer account.
isolated function memoryAddDeliveryAddress(string customerId, DeliveryAddress address)
        returns DeliveryAddress|error {
    lock {
        Customer? customer = customerTable[customerId];
        if customer is () {
            return error(string `Customer '${customerId}' was not found`);
        }
        DeliveryAddress storedAddress = address.clone();
        foreach DeliveryAddress existingAddress in customer.addresses {
            if existingAddress.addressId == storedAddress.addressId {
                return error(string `Address '${storedAddress.addressId}' already exists`);
            }
        }
        customer.addresses.push(storedAddress);
        return storedAddress.clone();
    }
}

// Records an order reference once for the customer's history view.
isolated function memoryRecordHistoricalOrder(string customerId, string orderId)
        returns Customer|error {
    lock {
        Customer? customer = customerTable[customerId];
        if customer is () {
            return error(string `Customer '${customerId}' was not found`);
        }
        if customer.historicalOrderIds.indexOf(orderId) is () {
            customer.historicalOrderIds.push(orderId);
        }
        return customer.clone();
    }
}

// Clears repository state for deterministic tests.
public isolated function clearCustomers() {
    lock {
        customerTable = table [];
    }
}

