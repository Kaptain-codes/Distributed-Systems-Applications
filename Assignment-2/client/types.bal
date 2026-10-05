public type ApiResult record {|
    int status;
    json body;
    string url;
|};

public type ClientState record {|
    string? customerId = ();
    string? addressId = ();
    json? address = ();
    string baseUrl = "http://localhost:9090/api";
    int pollMs = 2000;
    string? activeOrderId = ();
    json[] drivers = [];
|};

public type DriverSummary record {|
    string id;
    string name;
|};

public type OrderItem record {|
    string menuItemId;
    int qty;
|};
