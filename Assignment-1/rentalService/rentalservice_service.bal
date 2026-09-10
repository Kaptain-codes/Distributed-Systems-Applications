import ballerina/grpc;

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
