import ballerina/http;

public enum DriverStatus {
    AVAILABLE, ASSIGNED, OFFLINE
}

public enum DeliveryStatus {
    ASSIGNED, PICKED_UP, IN_TRANSIT, DELIVERED, CANCELLED
}

public type Driver record {|
    readonly string driverId;
    string fullName;
    string phoneNumber;
    string vehicleRegistration;
    DriverStatus status = AVAILABLE;
|};

public type DeliveryAssignmentRequest record {|
    readonly string deliveryId;
    string orderId;
    string driverId;
    string restaurantAddress;
    string customerAddress;
    string assignedAt;
|};

public type Delivery record {|
    readonly string deliveryId;
    string orderId;
    string driverId;
    string restaurantAddress;
    string customerAddress;
    DeliveryStatus status;
    string assignedAt;
    string updatedAt;
|};

public type DeliveryStatusUpdate record {|
    DeliveryStatus status;
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

