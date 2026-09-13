import ballerina/io;

RentalServiceClient ep = check new ("http://localhost:9091");

public function main() returns error? {
    AddPropertyRequest addPropertyRequest = {hostId: "ballerina", name: "ballerina", location: "ballerina", region: "ballerina", propertyType: "PROPERTY_TYPE_UNSPECIFIED", pricePerNight: 1, status: "PROPERTY_STATUS_UNSPECIFIED"};
    AddPropertyResponse addPropertyResponse = check ep->AddProperty(addPropertyRequest);
    io:println(addPropertyResponse);

    UpdatePropertyRequest updatePropertyRequest = {propertyId: "ballerina", hostId: "ballerina"};
    UpdatePropertyResponse updatePropertyResponse = check ep->UpdateProperty(updatePropertyRequest);
    io:println(updatePropertyResponse);

    RemovePropertyRequest removePropertyRequest = {propertyId: "ballerina", hostId: "ballerina"};
    RemovePropertyResponse removePropertyResponse = check ep->RemoveProperty(removePropertyRequest);
    io:println(removePropertyResponse);

    SearchPropertyRequest searchPropertyRequest = {propertyId: "ballerina"};
    SearchPropertyResponse searchPropertyResponse = check ep->SearchProperty(searchPropertyRequest);
    io:println(searchPropertyResponse);

    BookPropertyRequest bookPropertyRequest = {guestId: "ballerina", propertyId: "ballerina", checkIn: "ballerina", checkOut: "ballerina"};
    BookPropertyResponse bookPropertyResponse = check ep->BookProperty(bookPropertyRequest);
    io:println(bookPropertyResponse);

    ConfirmBookingRequest confirmBookingRequest = {guestId: "ballerina", cartItemId: "ballerina"};
    ConfirmBookingResponse confirmBookingResponse = check ep->ConfirmBooking(confirmBookingRequest);
    io:println(confirmBookingResponse);

    ListAvailablePropertiesRequest listAvailablePropertiesRequest = {};
    stream<Property, error?> listAvailablePropertiesResponse = check ep->ListAvailableProperties(listAvailablePropertiesRequest);
    check listAvailablePropertiesResponse.forEach(function(Property value) {
        io:println(value);
    });

    User createUsersRequest = {userId: "ballerina", name: "ballerina", email: "ballerina", role: "USER_ROLE_UNSPECIFIED"};
    CreateUsersStreamingClient createUsersStreamingClient = check ep->CreateUsers();
    check createUsersStreamingClient->sendUser(createUsersRequest);
    check createUsersStreamingClient->complete();
    CreateUsersResponse? createUsersResponse = check createUsersStreamingClient->receiveCreateUsersResponse();
    io:println(createUsersResponse);
}
