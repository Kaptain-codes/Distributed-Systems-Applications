import ballerina/http;

public enum PaymentStatus {
    PENDING,
    COMPLETED,
    FAILED,
    REFUNDED
}

public type PaymentRequest record {|
    readonly string paymentId;
    string orderId;
    string customerId;
    decimal amount;
    string currency = "NAD";
    string requestedAt;
|};

public type Payment record {|
    readonly string paymentId;
    string orderId;
    string customerId;
    decimal amount;
    string currency;
    PaymentStatus status;
    string requestedAt;
    string? processedAt = ();
    string? failureReason = ();
|};

// Deterministic simulation input; a real payment gateway replaces this later.
public type PaymentDecision record {|
    boolean approved;
    string processedAt;
    string? failureReason = ();
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

