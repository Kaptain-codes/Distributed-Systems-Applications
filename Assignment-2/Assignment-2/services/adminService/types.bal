import ballerina/http;

// Read-model statistics for one restaurant.
public type RestaurantStatistics record {|
    readonly string restaurantId;
    string restaurantName;
    int totalOrders;
    int completedOrders;
    int cancelledOrders;
    decimal grossRevenue;
|};

// Read-model performance measurements for one driver.
public type DeliveryPerformance record {|
    readonly string driverId;
    string driverName;
    int assignedDeliveries;
    int completedDeliveries;
    decimal averageDeliveryMinutes;
|};

public type PlatformSummary record {|
    int restaurantCount;
    int totalOrders;
    int completedOrders;
    int cancelledOrders;
    decimal grossRevenue;
    int activeDriverCount;
    int completedDeliveries;
|};

public type ErrorMessage record {|
    string message;
|};

public type BadRequestResponse record {|
    *http:BadRequest;
    ErrorMessage body;
|};

