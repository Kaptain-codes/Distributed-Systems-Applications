import ballerina/test;
import ballerina/http;

@test:Config {}
function testTargetMapping() {
    test:assertEquals(targetFor("customer", ["customers", "1"]), "/customer/customers/1");
    test:assertEquals(targetFor("restaurant", ["orders", "1", "accept"]), "/restaurant/orders/1/accept");
    test:assertEquals(targetFor("order", ["orders"]), "/order/orders");
    test:assertEquals(targetFor("payment", ["payments", "1"]), "/payment/payments/1");
    test:assertEquals(targetFor("delivery", ["deliveries", "1"]), "/delivery/deliveries/1");
    test:assertEquals(targetFor("notification", ["notifications", "1"]), "/notification/notifications/1");
    test:assertEquals(targetFor("admin", ["dlq"]), "/admin/dlq");
}

@test:Config {}
function testInternalAndUnknownServiceRejection() {
    test:assertFalse(isPublicPath(["orders", "internal", "1"]));
    test:assertTrue(isPublicPath(["orders", "1"]));
    test:assertTrue(clientFor("unknown") is ());
}

@test:Config {}
function testTransportErrorMapping() {
    test:assertEquals(transportStatus(error("connection refused")), 503);
    test:assertEquals(transportStatus(error("timeout waiting for response")), 503);
    test:assertEquals(transportStatus(error("invalid response")), 502);
}

@test:Config {}
function testOutboundBodyAndHeaderPassthrough() {
    http:Request inbound = new;
    inbound.setTextPayload("{\"value\":1}", "application/json");
    inbound.setHeader("X-Correlation-Id", "correlation-1");
    inbound.setHeader("X-Driver-Id", "driver-1");
    http:Request outbound = outboundRequest(inbound);
    test:assertEquals(outbound.getTextPayload(), "{\"value\":1}");
    test:assertEquals(outbound.getHeader("X-Correlation-Id"), "correlation-1");
    test:assertEquals(outbound.getHeader("X-Driver-Id"), "driver-1");
}

@test:Config {}
function testErrorResponsePassthroughShape() {
    http:Response response = errorResponse(409, "CONFLICT", "rejected");
    json expected = {"error": "CONFLICT", "message": "rejected"};
    test:assertEquals(response.statusCode, 409);
    test:assertEquals(response.getJsonPayload(), expected);
}
