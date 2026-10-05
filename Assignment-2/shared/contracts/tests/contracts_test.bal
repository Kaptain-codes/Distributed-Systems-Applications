import ballerina/test;

@test:Config {}
function topicInventoryHasExactlyTwentyThreeBaseTopics() {
    test:assertEquals(BASE_TOPICS.length(), 23);
    test:assertTrue(isBaseTopic("payment.requested"));
    test:assertTrue(isBaseTopic("delivery.picked_up"));
    test:assertFalse(isBaseTopic("orders.created.dlq"));
}

@test:Config {}
function dlqNamesUseLowercaseSuffix() {
    test:assertEquals(dlqTopic("orders.created"), "orders.created.dlq");
}
