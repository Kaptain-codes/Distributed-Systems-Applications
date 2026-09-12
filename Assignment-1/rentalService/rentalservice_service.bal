import ballerina/grpc;

<<<<<<< HEAD
listener grpc:Listener ep = new (9091);

@grpc:Descriptor {value: RENTAL_DESC}
service "RentalService" on ep {

    remote function AddProperty(AddPropertyRequest req)
            returns AddPropertyResponse|error {

        // 1. Validate
        if req.hostId.trim() == "" {
            return {success: false, message: "Host ID is required"};
        }
        if req.name.trim() == "" {
            return {success: false, message: "Property name is required"};
        }
        if req.location.trim() == "" {
            return {success: false, message: "Location is required"};
        }
        if req.region.trim() == "" {
            return {success: false, message: "Region is required"};
        }
        if req.pricePerNight <= 0.0 {
            return {success: false, message: "Price must be greater than zero"};
        }
        if req.propertyType == PROPERTY_TYPE_UNSPECIFIED {
            return {success: false, message: "Property type is required"};
        }
        if req.status == PROPERTY_STATUS_UNSPECIFIED {
            return {success: false, message: "Status is required"};
        }

        Property|error result = addProperty({
            propertyId: "", // repository assigns
            hostId: req.hostId,
            name: req.name,
            location: req.location,
            region: req.region,
            propertyType: req.propertyType,
            pricePerNight: req.pricePerNight,
            status: req.status
        });

        if result is error {
            return {success: false, message: result.message()};
        }
        return {
            success: true,
            message: "Property added",
            propertyId: result.propertyId
        };
    }

    remote function UpdateProperty(UpdatePropertyRequest req)
            returns UpdatePropertyResponse|error {

        if req.propertyId.trim() == "" {
            return {success: false, message: "Property ID is required"};
        }
        if req.hostId.trim() == "" {
            return {success: false, message: "Host ID is required"};
        }

        float? newPrice = req?.pricePerNight;
        if newPrice is float && newPrice <= 0.0 {
            return {success: false, message: "Price must be greater than zero"};
        }

        Property|error result = updateProperty(
            req.propertyId,
            req.hostId,
            req?.name,
            req?.location,
            newPrice,
            req?.status,
            req?.propertyType
        );

        if result is error {
            return {success: false, message: result.message()};
        }
        return {
            success: true,
            message: "Property updated",
            property: result
        };
    }

    remote function RemoveProperty(RemovePropertyRequest req)
            returns RemovePropertyResponse|error {

        if req.propertyId.trim() == "" {
            return {success: false, message: "Property ID is required"};
        }
        if req.hostId.trim() == "" {
            return {success: false, message: "Host ID is required"};
        }

        Property|error existing = getProperty(req.propertyId);
        if existing is error {
            return {success: false, message: existing.message()};
        }
        string region = existing.region;

        error? removed = removeProperty(req.propertyId, req.hostId);
        if removed is error {
            return {success: false, message: removed.message()};
        }

        Property[] remaining = getAvailableByRegion(region);
        return {
            success: true,
            message: "Property removed",
            region: region,
            properties: remaining,
            count: remaining.length()
        };
    }

isolated remote function CreateUsers(stream<User, grpc:Error?> clientStream)
        returns CreateUsersResponse|error {

    string[] created = [];
    UserCreationError[] failures = [];


    record {|User value;|}|grpc:Error? next = clientStream.next();
    while next is record {|User value;|} {
        User u = next.value;
        User|error result = addUser(u);
        if result is error {
            failures.push({userId: u.userId, reason: result.message()});
        } else {
            created.push(result.userId);
        }
        next = clientStream.next();
    }
    if next is grpc:Error {
        return next;
    }

    return {
        success: failures.length() == 0,
        message: string `${created.length()} created, ` +
                 string `${failures.length()} failed`,
        createdCount: created.length(),
        createdUserIds: created,
        failedCount: failures.length(),
        errors: failures
    };
}

    remote function ListAvailableProperties(ListAvailablePropertiesRequest req)
            returns stream<Property, error?>|error {

        Property[] matches = filterAvailable(
            req?.location,
            req?.minPrice,
            req?.maxPrice
        );
        return matches.toStream();
    }

    remote function SearchProperty(SearchPropertyRequest req)
            returns SearchPropertyResponse|error {

        Property|error result = getProperty(req.propertyId);
        if result is error {
            return {success: false, message: "Not Available"};
        }
        return {success: true, message: "Available", property: result};
    }

    remote function BookProperty(BookPropertyRequest req)
            returns BookPropertyResponse|error {

        if req.guestId.trim() == "" {
            return {success: false, message: "Guest ID is required"};
        }
        if !isValidDate(req.checkIn) || !isValidDate(req.checkOut) {
            return {success: false, message: "Dates must be YYYY-MM-DD"};
        }
        if req.checkIn >= req.checkOut {
            return {success: false, message: "Check-out must be after check-in"};
        }

        Property|error prop = getProperty(req.propertyId);
        if prop is error {
            return {success: false, message: "Property not found"};
        }
        if prop.status != AVAILABLE {
            return {success: false, message: "Property is not available"};
        }

        int nights = check nightsBetween(req.checkIn, req.checkOut);
        decimal estimate = <decimal>prop.pricePerNight * nights;

        CartItem|error item = addCartItem({
            cartItemId: "", // repository assigns
            guestId: req.guestId,
            propertyId: prop.propertyId,
            checkIn: req.checkIn,
            checkOut: req.checkOut,
            nights: nights,
            estimatedCost: estimate
        });

        if item is error {
            return {success: false, message: item.message()};
        }
        return {
            success: true,
            message: "Added to booking cart",
            cartItemId: item.cartItemId,
            nights: nights,
            estimatedCost: <float>estimate
        };
    }

    remote function ConfirmBooking(ConfirmBookingRequest req)
            returns ConfirmBookingResponse|error {

        CartItem|error item = getCartItem(req.cartItemId, req.guestId);
        if item is error {
            return {success: false, message: item.message()};
        }

        boolean clash = hasOverlappingBooking(
            item.propertyId,
            item.checkIn,
            item.checkOut
        );
        if clash {
            return {success: false,
                    message: "Those dates are no longer available"};
        }

        Property|error prop = getProperty(item.propertyId);
        if prop is error {
            return {success: false, message: "Property no longer exists"};
        }

        decimal finalCost = <decimal>prop.pricePerNight * item.nights;

        Booking|error booking = addBooking({
            bookingId: "", // repository assigns
            propertyId: item.propertyId,
            guestId: item.guestId,
            checkIn: item.checkIn,
            checkOut: item.checkOut,
            totalCost: <float>finalCost,
            nights: item.nights
        });

        if booking is error {
            return {success: false, message: booking.message()};
        }

        removeCartItem(item.cartItemId);

        return {
            success: true,
            message: "Booking confirmed",
            booking: booking
        };
    }
}
=======
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
>>>>>>> 2f44e7551db2b8dcc7b2b106af098b2f127b9876
