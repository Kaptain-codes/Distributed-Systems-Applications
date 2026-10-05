import ballerina/test;

@test:Config {}
function testReadIdFromTopLevel() {
    test:assertEquals(readId({customerId: "cus-1"}, "id", "customerId"), "cus-1");
}

@test:Config {}
function testReadIdFromNestedBody() {
    test:assertEquals(readId({body: {id: "addr-1"}}, "id", "addressId"), "addr-1");
}

@test:Config {}
function testPlaceOrderPayloadContainsNoGeneratedId() {
    json payload = buildPlaceOrderPayload("cus-1", "res-1", "addr-1", "item-1", 2, "SIM_OK");
    test:assertFalse(payload.toJsonString().includes("\"id\""));
    test:assertEquals((<map<json>>payload)["items"], [{menuItemId: "item-1", qty: 2}]);
}

@test:Config {}
function testRegisterPayloads() {
    json customer = buildRegisterCustomerPayload();
    json address = buildAddressPayload();
    test:assertTrue(customer is map<json> && customer["name"] == "Demo Customer");
    test:assertTrue(address is map<json> && address["is_default"] == true);
}
