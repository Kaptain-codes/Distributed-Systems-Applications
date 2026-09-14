import ballerina/io;

RentalServiceClient ep = check new ("http://localhost:9092");

const string HOST_ID = "HOST-001";
const string GUEST_ID = "GUEST-001";

function addProperty() returns string|error {
    AddPropertyResponse response = check ep->AddProperty({
        hostId: HOST_ID,
        name: "Seaside Cottage",
        location: "Brighton",
        region: "East Sussex",
        propertyType: COTTAGE,
        pricePerNight: 150.0,
        status: AVAILABLE
    });
    io:println(response);
    if !response.success || response.propertyId == "" {
        return error(response.message);
    }
    io:println("Saved property ID: ", response.propertyId);
    return response.propertyId;
}

function updateProperty(string propertyId) returns error? {
    UpdatePropertyResponse response = check ep->UpdateProperty({
        propertyId: propertyId,
        hostId: HOST_ID,
        name: "Updated Seaside Cottage",
        location: "Brighton",
        propertyType: COTTAGE,
        pricePerNight: 175.0,
        status: AVAILABLE
    });
    io:println(response);
    if !response.success {
        return error(response.message);
    }
}

function removeProperty(string propertyId) returns error? {
    RemovePropertyResponse response = check ep->RemoveProperty({
        propertyId: propertyId,
        hostId: HOST_ID
    });
    io:println(response);
    if !response.success {
        return error(response.message);
    }
}

function searchProperty(string propertyId) returns error? {
    SearchPropertyResponse response = check ep->SearchProperty({
        propertyId: propertyId
    });
    io:println(response);
    if !response.success {
        return error(response.message);
    }
}

function bookProperty(string propertyId) returns string|error {
    BookPropertyResponse response = check ep->BookProperty({
        guestId: GUEST_ID,
        propertyId: propertyId,
        checkIn: "2026-10-01",
        checkOut: "2026-10-05"
    });
    io:println(response);
    if !response.success || response.cartItemId == "" {
        return error(response.message);
    }
    io:println("Saved cart item ID: ", response.cartItemId);
    return response.cartItemId;
}

function confirmBooking(string cartItemId) returns error? {
    ConfirmBookingResponse response = check ep->ConfirmBooking({
        guestId: GUEST_ID,
        cartItemId: cartItemId
    });
    io:println(response);
    if !response.success {
        return error(response.message);
    }
}

function listAvailableProperties() returns error? {
    ListAvailablePropertiesRequest request = {};
    stream<Property, error?> properties =
        check ep->ListAvailableProperties(request);
    check properties.forEach(function(Property property) {
        io:println(property);
    });
}

function createUsers() returns error? {
    User hostUser = {
        userId: HOST_ID,
        name: "Host One",
        email: "host-001@example.com",
        role: HOST
    };
    User guestUser = {
        userId: GUEST_ID,
        name: "Guest One",
        email: "guest-001@example.com",
        role: GUEST
    };

    CreateUsersStreamingClient streamClient = check ep->CreateUsers();
    check streamClient->sendUser(hostUser);
    check streamClient->sendUser(guestUser);
    check streamClient->complete();

    CreateUsersResponse? response =
        check streamClient->receiveCreateUsersResponse();
    io:println(response);
}

function printError(error err) {
    io:println("Operation failed: ", err.message());
}

public function main() returns error? {
    string? savedPropertyId = ();
    string? savedCartItemId = ();
    boolean running = true;

    while running {
        io:println();
        io:println("1. Add property");
        io:println("2. Update property");
        io:println("3. Remove property");
        io:println("4. Search property");
        io:println("5. Book property");
        io:println("6. Confirm booking");
        io:println("7. List available properties");
        io:println("8. Create users");
        io:println("0. Exit");

        string choice = io:readln();
        match choice.trim() {
            "1" => {
                string|error propertyId = addProperty();
                if propertyId is error {
                    printError(propertyId);
                } else {
                    savedPropertyId = propertyId;
                }
            }
            "2" => {
                if savedPropertyId is string {
                    error? result = updateProperty(savedPropertyId);
                    if result is error {
                        printError(result);
                    }
                } else {
                    io:println("Please add a property first.");
                }
            }
            "3" => {
                if savedPropertyId is string {
                    error? result = removeProperty(savedPropertyId);
                    if result is error {
                        printError(result);
                    } else {
                        savedPropertyId = ();
                    }
                } else {
                    io:println("Please add a property first.");
                }
            }
            "4" => {
                if savedPropertyId is string {
                    error? result = searchProperty(savedPropertyId);
                    if result is error {
                        printError(result);
                    }
                } else {
                    io:println("Please add a property first.");
                }
            }
            "5" => {
                if savedPropertyId is string {
                    string|error cartItemId = bookProperty(savedPropertyId);
                    if cartItemId is error {
                        printError(cartItemId);
                    } else {
                        savedCartItemId = cartItemId;
                    }
                } else {
                    io:println("Please add a property first.");
                }
            }
            "6" => {
                if savedCartItemId is string {
                    error? result = confirmBooking(savedCartItemId);
                    if result is error {
                        printError(result);
                    } else {
                        savedCartItemId = ();
                    }
                } else {
                    io:println("Please book a property first.");
                }
            }
            "7" => {
                error? result = listAvailableProperties();
                if result is error {
                    printError(result);
                }
            }
            "8" => {
                error? result = createUsers();
                if result is error {
                    printError(result);
                }
            }
            "0" => {
                running = false;
            }
            _ => {
                io:println("Invalid option.");
            }
        }
    }
}
