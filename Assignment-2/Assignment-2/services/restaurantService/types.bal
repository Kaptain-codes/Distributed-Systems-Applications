import ballerina/http;

public type OpeningHours record {|
    string dayOfWeek;
    string opensAt;
    string closesAt;
    boolean closed = false;
|};

public type MenuItem record {|
    readonly string menuItemId;
    string name;
    string description;
    decimal price;
    int availableQuantity;
    boolean available = true;
|};

public type Restaurant record {|
    readonly string restaurantId;
    string name;
    string address;
    boolean acceptingOrders = true;
    OpeningHours[] openingHours = [];
    MenuItem[] menu = [];
|};

public type InventoryUpdate record {|
    int availableQuantity;
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

