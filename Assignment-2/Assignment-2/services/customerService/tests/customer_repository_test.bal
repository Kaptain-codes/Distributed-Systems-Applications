import ballerina/test;

@test:BeforeEach
function resetCustomerRepository() {
    clearCustomers();
}

@test:Config
function testCustomerRegistrationAndAddress() returns error? {
    Customer customer = check createCustomer({
                                                 customerId: "CUS-001",
                                                 fullName: "Anna Shikongo",
                                                 email: "anna@example.com",
                                                 phoneNumber: "+264811234567"
                                             });
    test:assertEquals(customer.fullName, "Anna Shikongo");

    DeliveryAddress address = check addDeliveryAddress("CUS-001", {
                                                                      addressId: "ADDR-001",
                                                                      label: "Home",
                                                                      street: "13 Independence Avenue",
                                                                      city: "Windhoek"
                                                                  });
    test:assertEquals(address.city, "Windhoek");
    Customer? storedCustomer = check findCustomer("CUS-001");
    test:assertTrue(storedCustomer is Customer);
    if storedCustomer is Customer {
        test:assertEquals(storedCustomer.addresses.length(), 1);
    }
}

@test:Config
function testDuplicateEmailIsRejected() {
    Customer firstCustomer = checkpanic createCustomer({
                                                           customerId: "CUS-001",
                                                           fullName: "Anna",
                                                           email: "same@example.com",
                                                           phoneNumber: "1"
                                                       });
    test:assertEquals(firstCustomer.customerId, "CUS-001");
    Customer|error duplicate = createCustomer({
                                                  customerId: "CUS-002",
                                                  fullName: "Ben",
                                                  email: "same@example.com",
                                                  phoneNumber: "2"
                                              });
    test:assertTrue(duplicate is error);
}
