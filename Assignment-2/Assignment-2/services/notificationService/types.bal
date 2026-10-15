import ballerina/http;

public enum NotificationChannel {
    EMAIL, SMS, PUSH
}

public enum RecipientType {
    CUSTOMER, RESTAURANT, DRIVER
}

public enum NotificationStatus {
    PENDING, SENT, FAILED
}

public type NotificationRequest record {|
    readonly string notificationId;
    RecipientType recipientType;
    string recipientId;
    NotificationChannel channel;
    string subject;
    string message;
    string createdAt;
|};

public type Notification record {|
    readonly string notificationId;
    RecipientType recipientType;
    string recipientId;
    NotificationChannel channel;
    string subject;
    string message;
    NotificationStatus status;
    string createdAt;
    string? sentAt = ();
|};

public type DeliveryResult record {|
    boolean successful;
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

