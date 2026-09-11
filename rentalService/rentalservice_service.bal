import ballerina/grpc;

@grpc:Descriptor {value: RENTAL_DESC}
service "RentalService" on new grpc:Listener(9091) {

    remote function AddProperty(AddPropertyRequest value) returns AddPropertyResponse|error {
        Property p = addProperty(value.hostId, value.name, value.location, value.region, value.propertyType, value.pricePerNight, value.status);
        return {
            success: true,
            message: "Property successfully added.",
            propertyId: p.propertyId
        };
    }

    remote function UpdateProperty(UpdatePropertyRequest value) returns UpdatePropertyResponse|error {
        string? nameParam = value.name is string ? value.name : ();
        string? locationParam = value.location is string ? value.location : ();
        float? priceParam = value.pricePerNight;
        PropertyStatus? statusParam = value.status;
        PropertyType? typeParam = value.propertyType;

        Property|error updated = updateProperty(value.propertyId, value.hostId, nameParam, locationParam, priceParam, statusParam, typeParam);
        if updated is error {
            return {
                success: false,
                message: updated.message(),
                property: {propertyId: "", hostId: "", name: "", location: "", region: "", propertyType: PROPERTY_TYPE_UNSPECIFIED, pricePerNight: 0.0, status: PROPERTY_STATUS_UNSPECIFIED}
            };
        }
        return {
            success: true,
            message: "Property successfully updated.",
            property: updated
        };
    }

    remote function RemoveProperty(RemovePropertyRequest value) returns RemovePropertyResponse|error {
        [string, Property[]]|error res = removeProperty(value.propertyId, value.hostId);
        if res is error {
            return {
                success: false,
                message: res.message(),
                region: "",
                count: 0,
                properties: []
            };
        }
        string region = res[0];
        Property[] props = res[1];
        return {
            success: true,
            message: "Property removed successfully.",
            region: region,
            count: <int>props.length(),
            properties: props
        };
    }

    remote function CreateUsers(stream<User, grpc:Error?> clientStream) returns CreateUsersResponse|error {
        int createdCount = 0;
        string[] createdUserIds = [];
        int failedCount = 0;
        UserCreationError[] errors = [];

        record {|User value;|}|grpc:Error? clientData = clientStream.next();
        while clientData is record {|User value;|} {
            User u = clientData.value;
            User|error result = addUser(u);
            if result is error {
                failedCount += 1;
                errors.push({ userId: u.userId, reason: result.message() });
            } else {
                createdCount += 1;
                createdUserIds.push(result.userId);
            }
            clientData = clientStream.next();
        }

        return {
            success: failedCount == 0,
            message: failedCount == 0 ? "All users created successfully." : "Completed with some failures.",
            createdCount: createdCount,
            createdUserIds: createdUserIds,
            failedCount: failedCount,
            errors: errors
        };
    }

    remote function ListAvailableProperties(ListAvailablePropertiesRequest value) returns stream<Property, grpc:Error?>|error {
        string? loc = value.location;
        float? min = value.minPrice;
        float? max = value.maxPrice;

        Property[] properties = filterAvailableProperties(loc, min, max);
        return properties.toStream();
    }

    remote function SearchProperty(SearchPropertyRequest value) returns SearchPropertyResponse|error {
        Property|error p = getProperty(value.propertyId);
        if p is error {
            return {
                success: false,
                message: "Property not found.",
                property: ()
            };
        }
        return {
            success: true,
            message: "Available",
            property: p
        };
    }

    remote function BookProperty(BookPropertyRequest value) returns BookPropertyResponse|error {
        Property|error p = getProperty(value.propertyId);
        if p is error {
            return {
                success: false,
                message: "Property not found.",
                cartItemId: "",
                nights: 0,
                estimatedCost: 0.0
            };
        }
        if p.status != AVAILABLE {
            return {
                success: false,
                message: "Property is not available.",
                cartItemId: "",
                nights: 0,
                estimatedCost: 0.0
            };
        }

        int nights = nightsBetween(value.checkIn, value.checkOut);
        if nights <= 0 {
            return {
                success: false,
                message: "Invalid check-in or check-out dates.",
                cartItemId: "",
                nights: 0,
                estimatedCost: 0.0
            };
        }

        float estimatedCost = <float>nights * p.pricePerNight;
        CartItem item = addCartItem(value.guestId, value.propertyId, value.checkIn, value.checkOut, estimatedCost, nights);
        
        return {
            success: true,
            message: "Booking request added to cart.",
            cartItemId: item.cartItemId,
            nights: nights,
            estimatedCost: estimatedCost
        };
    }

remote function ConfirmBooking(ConfirmBookingRequest value) returns ConfirmBookingResponse|error {
        CartItem|error item = getCartItem(value.cartItemId, value.guestId);
        if item is error {
            return {
                success: false,
                message: item.message(),
                booking: ()
            };
        }

        boolean overlapped = hasOverlappingBooking(item.propertyId, item.checkIn, item.checkOut);
        if overlapped {
            return {
                success: false,
                message: "Property is already booked for these dates.",
                booking: ()
            };
        }

        Booking booking = addBooking(item.propertyId, item.guestId, item.checkIn, item.checkOut, item.estimatedCost, item.nights);
        
        Property|error prop = getProperty(item.propertyId);
        if prop is Property {
            _ = check updateProperty(item.propertyId, prop.hostId, (), (), (), (), ());
        }
        
        removeCartItem(value.cartItemId);

        return {
            success: true,
            message: "Booking confirmed successfully.",
            booking: booking
        };
    }
}