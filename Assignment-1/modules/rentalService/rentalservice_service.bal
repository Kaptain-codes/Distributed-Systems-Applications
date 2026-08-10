import ballerina/grpc;

listener grpc:Listener ep = new (9090);

@grpc:Descriptor {value: RENTAL_DESC}
service "RentalService" on ep {

    remote function AddProperty(AddPropertyRequest value) returns AddPropertyResponse|error {
    }

    remote function UpdateProperty(UpdatePropertyRequest value) returns UpdatePropertyResponse|error {
    }

    remote function RemoveProperty(RemovePropertyRequest value) returns RemovePropertyResponse|error {
    }

    remote function SearchProperty(SearchPropertyRequest value) returns SearchPropertyResponse|error {
    }

    remote function BookProperty(BookPropertyRequest value) returns BookPropertyResponse|error {
    }

    remote function ConfirmBooking(ConfirmBookingRequest value) returns ConfirmBookingResponse|error {
    }

    remote function CreateUsers(stream<User, grpc:Error?> clientStream) returns CreateUsersResponse|error {
    }

    remote function ListAvailableProperties(ListAvailablePropertiesRequest value) returns stream<Property, error?>|error {
    }
}
