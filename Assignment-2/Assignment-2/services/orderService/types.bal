import ballerina/http;

// States in the assignment's canonical order lifecycle.
public enum OrderStatus {
    CREATED,
    CONFIRMED,
    PREPARING,
    READY,
    OUT_FOR_DELIVERY,
    DELIVERED,
    CANCELLED
}

// A menu item and quantity captured when the order is placed.
public type OrderItem record {|
    readonly string menuItemId;
    string itemName;
    int quantity;
    decimal unitPrice;
|};

// Input accepted when a customer places an order.
public type OrderCreateRequest record {|
    readonly string orderId;
    string customerId;
    string restaurantId;
    string deliveryAddressId;
    OrderItem[] items;
    decimal totalAmount;
    string createdAt;
|};

// The authoritative order aggregate managed only by this service.
public type FoodOrder record {|
    readonly string orderId;
    string customerId;
    string restaurantId;
    string deliveryAddressId;
    OrderItem[] items;
    decimal totalAmount;
    OrderStatus status;
    string createdAt;
    string updatedAt;
|};

// Request to move an order through its state machine.
public type OrderTransitionRequest record {|
    OrderStatus status;
    string occurredAt;
|};

public type ErrorMessage record {|
    string message;
|};

public type NotFoundResponse record {|
    *http:NotFound;
    ErrorMessage body;
|};

public type ConflictResponse record {|
    *http:Conflict;
    ErrorMessage body;
|};

public type BadRequestResponse record {|
    *http:BadRequest;
    ErrorMessage body;
|};

