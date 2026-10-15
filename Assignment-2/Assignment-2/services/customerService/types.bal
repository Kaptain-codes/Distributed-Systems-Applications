import ballerina/http;

// A delivery address owned by a customer.
public type DeliveryAddress record {|
    readonly string addressId;
    string label;
    string street;
    string city;
    string? deliveryInstructions = ();
|};

// A registered platform customer.
public type Customer record {|
    readonly string customerId;
    string fullName;
    string email;
    string phoneNumber;
    DeliveryAddress[] addresses = [];
    string[] historicalOrderIds = [];
|};

// Fields that a customer is allowed to change.
public type CustomerUpdate record {|
    string fullName;
    string email;
    string phoneNumber;
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

