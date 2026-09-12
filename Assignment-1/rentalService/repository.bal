isolated map<Property> propertyTable = {};
isolated map<User> userTable = {};
isolated map<Booking> bookingTable = {};
isolated map<CartItem> cartTable = {};

isolated int propertyCounter = 0;
isolated int bookingCounter = 0;
isolated int cartCounter = 0;

isolated function nextPropertyId() returns string {
    lock {
        propertyCounter += 1;
        return string `PROP-${propertyCounter.toString().padZero(3)}`;
    }
}

isolated function nextBookingId() returns string {
    lock {
        bookingCounter += 1;
        return string `BK-${bookingCounter.toString().padZero(3)}`;
    }
}

isolated function nextCartItemId() returns string {
    lock {
        cartCounter += 1;
        return string `CART-${cartCounter.toString().padZero(3)}`;
    }
}

public isolated function addProperty(string hostId, string name, string location, string region, PropertyType propertyType, float pricePerNight, PropertyStatus status) returns Property {
    string id = nextPropertyId();
    Property prop = {
        propertyId: id,
        hostId: hostId,
        name: name,
        location: location,
        region: region,
        propertyType: propertyType,
        pricePerNight: pricePerNight,
        status: status
    };
    lock {
        propertyTable[id] = prop.clone();
        return prop.cloneReadOnly();
    }
}

public isolated function getProperty(string propertyId) returns Property|error {
    lock {
        Property? p = propertyTable[propertyId];
        if p is () {
            return error("Property not found");
        }
        return p.cloneReadOnly();
    }
}

public isolated function updateProperty(string propertyId, string hostId, string? name, string? location, float? pricePerNight, PropertyStatus? status, PropertyType? propertyType) returns Property|error {
    lock {
        Property? existing = propertyTable[propertyId];
        if existing is () {
            return error("Property not found");
        }
        if existing.hostId != hostId {
            return error("Host does not own this property");
        }
        Property updated = existing.clone();
        if name is string { updated.name = name; }
        if location is string { updated.location = location; }
        if pricePerNight is float { updated.pricePerNight = pricePerNight; }
        if status is PropertyStatus { updated.status = status; }
        if propertyType is PropertyType { updated.propertyType = propertyType; }
        
        propertyTable[propertyId] = updated;
        return updated.cloneReadOnly();
    }
}

public isolated function removeProperty(string propertyId, string hostId) returns [string, Property[]]|error {
    lock {
        Property? existing = propertyTable[propertyId];
        if existing is () {
            return error("Property not found");
        }
        if existing.hostId != hostId {
            return error("Host does not own this property");
        }
        string region = existing.region.toUpperAscii();
        _ = propertyTable.remove(propertyId);

        Property[] remaining = [];
        foreach var p in propertyTable {
            if p.region.toUpperAscii() == region && p.status == AVAILABLE {
                remaining.push(p.clone());
            }
        }
        return [region, remaining.clone()];
    }
}

public isolated function addUser(User user) returns User|error {
    lock {
        if user.userId == "" {
            return error("User ID is required");
        }
        if userTable.hasKey(user.userId) {
            return error("User already exists");
        }
        User stored = user.clone();
        userTable[stored.userId] = stored;
        return stored.cloneReadOnly();
    }
}

public isolated function filterAvailableProperties(string? location, float? minPrice, float? maxPrice) returns Property[] {
    lock {
        Property[] results = [];
        foreach var p in propertyTable {
            if p.status != AVAILABLE {
                continue;
            }
            if location is string && p.location != location {
                continue;
            }
            if minPrice is float && p.pricePerNight < minPrice {
                continue;
            }
            if maxPrice is float && p.pricePerNight > maxPrice {
                continue;
            }
            results.push(p.clone());
        }
        return results.clone();
    }
}

public isolated function addCartItem(string guestId, string propertyId, string checkIn, string checkOut, float estimatedCost, int nights) returns CartItem {
    string id = nextCartItemId();
    CartItem item = {
        cartItemId: id,
        guestId: guestId,
        propertyId: propertyId,
        checkIn: checkIn,
        checkOut: checkOut,
        estimatedCost: estimatedCost,
        nights: nights
    };
    lock {
        cartTable[id] = item.clone();
        return item.cloneReadOnly();
    }
}

public isolated function getCartItem(string cartItemId, string guestId) returns CartItem|error {
    lock {
        CartItem? item = cartTable[cartItemId];
        if item is () {
            return error("Cart item not found");
        }
        if item.guestId != guestId {
            return error("Cart item does not belong to this guest");
        }
        return item.cloneReadOnly();
    }
}

public isolated function removeCartItem(string cartItemId) {
    lock {
        _ = cartTable.removeIfHasKey(cartItemId);
    }
}

public isolated function hasOverlappingBooking(string propertyId, string checkIn, string checkOut) returns boolean {
    lock {
        foreach var b in bookingTable {
            if b.propertyId == propertyId {
                if !(checkOut <= b.checkIn || checkIn >= b.checkOut) {
                    return true;
                }
            }
        }
        return false;
    }
}

public isolated function addBooking(string propertyId, string guestId, string checkIn, string checkOut, float totalCost, int nights) returns Booking {
    string id = nextBookingId();
    Booking booking = {
        bookingId: id,
        propertyId: propertyId,
        guestId: guestId,
        checkIn: checkIn,
        checkOut: checkOut,
        totalCost: totalCost,
        nights: nights
    };
    lock {
        bookingTable[id] = booking.clone();
        return booking.cloneReadOnly();
    }
}