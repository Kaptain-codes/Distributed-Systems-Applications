isolated map<Property> propertyTable = {};
<<<<<<< HEAD
isolated map<User>     userTable     = {};
isolated map<Booking>  bookingTable  = {};
isolated map<CartItem> cartTable     = {};

=======
isolated map<User> userTable = {};
isolated map<Booking> bookingTable = {};
isolated map<CartItem> cartTable = {};
>>>>>>> 2f44e7551db2b8dcc7b2b106af098b2f127b9876

isolated int propertyCounter = 0;
isolated int bookingCounter = 0;
isolated int cartCounter = 0;
<<<<<<< HEAD
=======

>>>>>>> 2f44e7551db2b8dcc7b2b106af098b2f127b9876
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

<<<<<<< HEAD
public isolated function addProperty(Property prop) returns Property|error {
    string id = nextPropertyId();
    lock {
        Property stored = prop.clone();
        stored.propertyId = id;
        stored.hostId   = normalizeId(prop.hostId);
        stored.name     = normalizeText(prop.name);
        stored.location = normalizeText(prop.location);
        stored.region   = normalizeId(prop.region);
        propertyTable[id] = stored;
        return stored.cloneReadOnly();
    }
}
public isolated function getProperty(string propertyId)
        returns Property|error {
    string id = normalizeId(propertyId);
    lock {
        Property? p = propertyTable[id];
        if p is () {
            return error PropertyNotFound("", id = propertyId,
                                          reason = "Property not found");
=======
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
>>>>>>> 2f44e7551db2b8dcc7b2b106af098b2f127b9876
        }
        return p.cloneReadOnly();
    }
}

<<<<<<< HEAD
public isolated function getAvailableByRegion(string region)
        returns Property[] & readonly {
    string r = normalizeId(region);
    lock {
        return from var p in propertyTable
               where p.region == r && p.status == AVAILABLE
               select p.cloneReadOnly();
    }
}

public isolated function updateProperty(string propertyId, string hostId,
        string? name, string? location, float? price,
        PropertyStatus? status, PropertyType? ptype)
        returns Property|error {
    string id = normalizeId(propertyId);
    lock {
        Property? existing = propertyTable[id];
        if existing is () {
            return error PropertyNotFound("", id = propertyId,
                                          reason = "Property not found");
        }
        if existing.hostId != normalizeId(hostId) {
            return error NotPropertyOwner("", id = propertyId,
                        reason = "Host does not own this property");
        }
        Property updated = existing.clone();
        if name is string     { updated.name = normalizeText(name); }
        if location is string { updated.location = normalizeText(location); }
        if price is float     { updated.pricePerNight = price; }
        if status is PropertyStatus { updated.status = status; }
        if ptype is PropertyType    { updated.propertyType = ptype; }
        propertyTable[id] = updated; 
=======
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
>>>>>>> 2f44e7551db2b8dcc7b2b106af098b2f127b9876
        return updated.cloneReadOnly();
    }
}

<<<<<<< HEAD
// Streams-in filter for ListAvailableProperties. A nil filter means
// "no constraint" - NOT "match zero". This is why the proto marks
// all three fields optional.
public isolated function filterAvailable(string? location, float? minPrice,
                                         float? maxPrice) returns Property[] {
    lock {
        Property[] result = [];
        foreach Property p in propertyTable {
            if p.status != AVAILABLE {
                continue;
            }
            if location is string && p.location.trim() != location.trim() {
=======
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
>>>>>>> 2f44e7551db2b8dcc7b2b106af098b2f127b9876
                continue;
            }
            if minPrice is float && p.pricePerNight < minPrice {
                continue;
            }
            if maxPrice is float && p.pricePerNight > maxPrice {
                continue;
            }
<<<<<<< HEAD
            result.push(p.clone());
        }
        return result.clone();
    }
}

public isolated function addUser(User user) returns User|error {
    string id = normalizeId(user.userId);
    if id == "" {
        return error ValidationError("", id = user.userId,
                                     reason = "User ID is required");
    }
    lock {
        if userTable.hasKey(id) {
            return error UserExists("", id = id,
                                    reason = "User ID already exists");
        }
        User stored = user.clone();
        stored.userId = id;
        stored.name = normalizeText(user.name);
        stored.email = normalizeText(user.email);
        userTable[id] = stored;
        return stored.clone();
    }
}

// Ownership is checked here, not in the handler - a guest must not be
// able to confirm another guest's cart entry by guessing an id.
public isolated function getCartItem(string cartItemId, string guestId)
        returns CartItem|error {
    string id = normalizeId(cartItemId);
    string guest = normalizeId(guestId);
    lock {
        CartItem? item = cartTable[id];
        if item is () {
            return error CartItemNotFound("", id = cartItemId,
                                          reason = "Cart item not found");
        }
        if item.guestId != guest {
            return error CartItemNotFound("", id = cartItemId,
                        reason = "Cart item does not belong to this guest");
        }
        return item.clone();
    }
}

// The core of ConfirmBooking. Only touches bookingTable, so a single
// lock covers it - no cross-table atomicity problem here.
public isolated function hasOverlappingBooking(string propertyId,
                                               string checkIn,
                                               string checkOut)
        returns boolean {
    string pid = normalizeId(propertyId);
    lock {
        foreach Booking b in bookingTable {
            if b.propertyId != pid {
                continue;
            }
            if datesOverlap(b.checkIn, b.checkOut, checkIn, checkOut) {
                return true;
=======
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
>>>>>>> 2f44e7551db2b8dcc7b2b106af098b2f127b9876
            }
        }
        return false;
    }
}

<<<<<<< HEAD
public isolated function addCartItem(CartItem item) returns CartItem|error {
    string id = nextCartItemId();
    lock {
        CartItem stored = item.clone();
        stored.cartItemId = id;
        cartTable[id] = stored;
        return stored.clone();
    }
}

public isolated function addBooking(Booking booking) returns Booking|error {
    string id = nextBookingId();
    lock {
        Booking stored = booking.clone();
        stored.bookingId = id;
        bookingTable[id] = stored;
        return stored.clone();
    }
}

// ConfirmBooking must clear the guest's temporary request - the brief
// says so explicitly, and without it a cart entry could be confirmed twice.
public isolated function removeCartItem(string cartItemId) {
    string id = normalizeId(cartItemId);
    lock {
        _ = cartTable.removeIfHasKey(id);
    }
}

public isolated function removeProperty(string propertyId, string hostId)
        returns error? {
    string id = normalizeId(propertyId);
    string host = normalizeId(hostId);
    lock {
        Property? existing = propertyTable[id];
        if existing is () {
            return error PropertyNotFound("", id = propertyId,
                                          reason = "Property not found");
        }
        if existing.hostId != host {
            return error NotPropertyOwner("", id = propertyId,
                        reason = "Host does not own this property");
        }
        _ = propertyTable.remove(id);
        return;
=======
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
>>>>>>> 2f44e7551db2b8dcc7b2b106af098b2f127b9876
    }
}