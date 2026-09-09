import ballerina/test;

// The generated RentalServiceClient lives in rental_pb.bal, in this
// same package - so the server can be tested without waiting for
// Person 4's client.
RentalServiceClient cl = check new ("http://localhost:9091");

// Shared across tests. Ballerina runs tests in declaration order
// within a file unless dependsOn says otherwise.
string testPropertyId = "";
string testCartItemId = "";


// =====================================================
// PURE FUNCTIONS - no server needed
// =====================================================

@test:Config {}
function testNormalizeId() {
    test:assertEquals(normalizeId("  prop-001  "), "PROP-001");
    test:assertEquals(normalizeId("host-1"), "HOST-1");
}

@test:Config {}
function testNightsBetween() returns error? {
    // 10th to 15th is 5 nights, 6 days. Checkout day is not a night.
    test:assertEquals(check nightsBetween("2026-09-10", "2026-09-15"), 5);
    test:assertEquals(check nightsBetween("2026-09-10", "2026-09-11"), 1);
    test:assertEquals(check nightsBetween("2026-12-30", "2027-01-02"), 3);
}

@test:Config {}
function testOverlapTruthTable() {
    string aIn = "2026-09-10";
    string aOut = "2026-09-15";

    // --- must overlap ---
    test:assertTrue(datesOverlap(aIn, aOut, "2026-09-12", "2026-09-18"),
            "starts inside the existing stay");
    test:assertTrue(datesOverlap(aIn, aOut, "2026-09-08", "2026-09-12"),
            "ends inside the existing stay");
    test:assertTrue(datesOverlap(aIn, aOut, "2026-09-11", "2026-09-14"),
            "entirely inside");
    test:assertTrue(datesOverlap(aIn, aOut, "2026-09-08", "2026-09-20"),
            "entirely contains it");
    test:assertTrue(datesOverlap(aIn, aOut, "2026-09-10", "2026-09-15"),
            "identical range");

    // --- must NOT overlap ---
    test:assertFalse(datesOverlap(aIn, aOut, "2026-09-20", "2026-09-25"),
            "starts after it ends");
    test:assertFalse(datesOverlap(aIn, aOut, "2026-09-01", "2026-09-05"),
            "ends before it starts");

    // Same-day turnover. A checkout on the 15th must NOT block a
    // check-in on the 15th - this is why the comparison is strict <.
    test:assertFalse(datesOverlap(aIn, aOut, "2026-09-15", "2026-09-20"),
            "turnover: check-in on the checkout day");
    test:assertFalse(datesOverlap(aIn, aOut, "2026-09-05", "2026-09-10"),
            "turnover: checkout on the check-in day");
}


// =====================================================
// USER MANAGEMENT - client streaming
// =====================================================

@test:Config {}
function testCreateUsersBatch() returns error? {
    CreateUsersStreamingClient sc = check cl->CreateUsers();
    check sc->sendUser({userId: "HOST-1", name: "Amos",
                        email: "amos@example.com", role: HOST});
    check sc->sendUser({userId: "GUEST-1", name: "Ndapewa",
                        email: "ndapewa@example.com", role: GUEST});
    check sc->sendUser({userId: "GUEST-2", name: "Tuyeni",
                        email: "tuyeni@example.com", role: GUEST});
    check sc->complete();   // server does not reply until the stream closes

    CreateUsersResponse? res = check sc->receiveCreateUsersResponse();
    test:assertTrue(res is CreateUsersResponse, "expected a response");
    if res is CreateUsersResponse {
        test:assertEquals(res.createdCount, 3);
        test:assertEquals(res.failedCount, 0);
        test:assertTrue(res.success, "a clean batch is a success");
    }
}

@test:Config {dependsOn: [testCreateUsersBatch]}
function testCreateUsersReportsDuplicates() returns error? {
    CreateUsersStreamingClient sc = check cl->CreateUsers();
    check sc->sendUser({userId: "HOST-1", name: "Duplicate",
                        email: "dupe@example.com", role: HOST});
    check sc->complete();

    CreateUsersResponse? res = check sc->receiveCreateUsersResponse();
    if res is CreateUsersResponse {
        test:assertEquals(res.failedCount, 1, "duplicate should fail");
        test:assertFalse(res.success, "a partial batch is not a success");
        test:assertEquals(res.errors.length(), 1,
                "failure should be reported structurally, not in prose");
    }
}


// =====================================================
// PROPERTY CRUD
// =====================================================

@test:Config {}
function testAddPropertyHappyPath() returns error? {
    AddPropertyResponse res = check cl->AddProperty({
        hostId: "HOST-1",
        name: "Kalahari Cottage",
        location: "12 Jackson Kaujeua Street",
        region: "Khomas",
        propertyType: COTTAGE,
        pricePerNight: 850.0,
        status: AVAILABLE
    });
    test:assertTrue(res.success, res.message);
    test:assertNotEquals(res.propertyId, "", "should return a generated id");
    testPropertyId = res.propertyId;
}

@test:Config {}
function testAddPropertyRejectsNegativePrice() returns error? {
    AddPropertyResponse res = check cl->AddProperty({
        hostId: "HOST-1",
        name: "Bad Listing",
        location: "Nowhere",
        region: "Khomas",
        propertyType: HOUSE,
        pricePerNight: -50.0,
        status: AVAILABLE
    });
    test:assertFalse(res.success, "negative price must be rejected");
}

@test:Config {}
function testAddPropertyRejectsEmptyName() returns error? {
    AddPropertyResponse res = check cl->AddProperty({
        hostId: "HOST-1",
        name: "",
        location: "Somewhere",
        region: "Khomas",
        propertyType: HOUSE,
        pricePerNight: 500.0,
        status: AVAILABLE
    });
    test:assertFalse(res.success, "empty name must be rejected");
}

@test:Config {}
function testAddPropertyRejectsUnspecifiedType() returns error? {
    AddPropertyResponse res = check cl->AddProperty({
        hostId: "HOST-1",
        name: "No Type",
        location: "Somewhere",
        region: "Khomas",
        propertyType: PROPERTY_TYPE_UNSPECIFIED,
        pricePerNight: 500.0,
        status: AVAILABLE
    });
    test:assertFalse(res.success,
            "UNSPECIFIED is the proto3 'unset' sentinel - reject it");
}

@test:Config {dependsOn: [testAddPropertyHappyPath]}
function testSearchPropertyFound() returns error? {
    SearchPropertyResponse res = check cl->SearchProperty(
            {propertyId: testPropertyId});
    test:assertTrue(res.success);
    test:assertEquals(res.message, "Available");
    test:assertTrue(res?.property is Property, "details should be populated");
}

@test:Config {}
function testSearchPropertyNotFound() returns error? {
    SearchPropertyResponse res = check cl->SearchProperty(
            {propertyId: "NOPE-999"});
    // The brief requires a "Not Available" status, not an exception.
    test:assertFalse(res.success);
    test:assertEquals(res.message, "Not Available");
    test:assertTrue(res?.property is (), "property should be nil, not empty");
}


// =====================================================
// PARTIAL UPDATE - proves proto3 `optional` works
// =====================================================

@test:Config {dependsOn: [testAddPropertyHappyPath]}
function testPartialUpdateLeavesOtherFieldsAlone() returns error? {
    UpdatePropertyResponse res = check cl->UpdateProperty({
        propertyId: testPropertyId,
        hostId: "HOST-1",
        pricePerNight: 999.0        // ONLY this field is sent
    });
    test:assertTrue(res.success, res.message);
    test:assertEquals(res.property.pricePerNight, 999.0);
    test:assertEquals(res.property.name, "Kalahari Cottage",
            "name must survive a price-only update");
    test:assertEquals(res.property.location, "12 Jackson Kaujeua Street",
            "location must survive a price-only update");
}

@test:Config {dependsOn: [testAddPropertyHappyPath]}
function testUpdateRejectsWrongOwner() returns error? {
    UpdatePropertyResponse res = check cl->UpdateProperty({
        propertyId: testPropertyId,
        hostId: "HOST-99",          // not the owner
        pricePerNight: 1.0
    });
    test:assertFalse(res.success, "a host must not edit another's listing");
}


// =====================================================
// SERVER STREAMING
// =====================================================

@test:Config {dependsOn: [testAddPropertyHappyPath]}
function testListStreamsOnlyAvailable() returns error? {
    stream<Property, error?> s = check cl->ListAvailableProperties({});
    int count = 0;
    check s.forEach(function(Property p) {
        count += 1;
        test:assertEquals(p.status, AVAILABLE,
                "only AVAILABLE properties should stream");
    });
    test:assertTrue(count > 0, "expected at least one property");
}

@test:Config {dependsOn: [testAddPropertyHappyPath]}
function testListWithNoFiltersReturnsEverything() returns error? {
    // An omitted minPrice means "no constraint", NOT "match zero".
    stream<Property, error?> s = check cl->ListAvailableProperties({});
    int count = 0;
    check s.forEach(function(Property p) {
        count += 1;
    });
    test:assertTrue(count > 0,
            "nil filters must not exclude everything");
}


// =====================================================
// BOOKING FLOW
// =====================================================

@test:Config {dependsOn: [testPartialUpdateLeavesOtherFieldsAlone]}
function testBookPropertyCalculatesNightsAndCost() returns error? {
    BookPropertyResponse res = check cl->BookProperty({
        guestId: "GUEST-1",
        propertyId: testPropertyId,
        checkIn: "2026-09-10",
        checkOut: "2026-09-15"
    });
    test:assertTrue(res.success, res.message);
    test:assertEquals(res.nights, 5, "10th to 15th is 5 nights");
    // price was updated to 999.0 by the partial-update test
    test:assertEquals(res.estimatedCost, 4995.0,
            "5 nights x 999.00 = 4995.00 exactly");
    testCartItemId = res.cartItemId;
    test:assertNotEquals(testCartItemId, "", "should return a cart handle");
}

@test:Config {dependsOn: [testAddPropertyHappyPath]}
function testBookRejectsReversedDates() returns error? {
    BookPropertyResponse res = check cl->BookProperty({
        guestId: "GUEST-1",
        propertyId: testPropertyId,
        checkIn: "2026-09-15",
        checkOut: "2026-09-10"
    });
    test:assertFalse(res.success, "check-out before check-in");
}

@test:Config {dependsOn: [testAddPropertyHappyPath]}
function testBookRejectsZeroNightStay() returns error? {
    BookPropertyResponse res = check cl->BookProperty({
        guestId: "GUEST-1",
        propertyId: testPropertyId,
        checkIn: "2026-09-10",
        checkOut: "2026-09-10"
    });
    test:assertFalse(res.success, "same day in and out is zero nights");
}

@test:Config {dependsOn: [testBookPropertyCalculatesNightsAndCost]}
function testConfirmBookingSucceeds() returns error? {
    ConfirmBookingResponse res = check cl->ConfirmBooking({
        guestId: "GUEST-1",
        cartItemId: testCartItemId
    });
    test:assertTrue(res.success, res.message);
    Booking? b = res?.booking;
    test:assertTrue(b is Booking, "booking should be populated");
    if b is Booking {
        test:assertEquals(b.nights, 5);
        test:assertEquals(b.totalCost, 4995.0);
    }
}

@test:Config {dependsOn: [testConfirmBookingSucceeds]}
function testCartIsClearedAfterConfirm() returns error? {
    // The brief requires clearing the guest's temporary request.
    // Without this the same stay could be booked twice.
    ConfirmBookingResponse res = check cl->ConfirmBooking({
        guestId: "GUEST-1",
        cartItemId: testCartItemId
    });
    test:assertFalse(res.success, "cart entry should already be gone");
}


// =====================================================
// THE CHECK THAT MATTERS MOST
// =====================================================

@test:Config {dependsOn: [testConfirmBookingSucceeds]}
function testOverlappingBookingIsRejected() returns error? {
    // 10-15 is already confirmed. 12-18 overlaps it.
    BookPropertyResponse booked = check cl->BookProperty({
        guestId: "GUEST-2",
        propertyId: testPropertyId,
        checkIn: "2026-09-12",
        checkOut: "2026-09-18"
    });
    test:assertTrue(booked.success, "carting is allowed - confirming is not");

    ConfirmBookingResponse res = check cl->ConfirmBooking({
        guestId: "GUEST-2",
        cartItemId: booked.cartItemId
    });
    test:assertFalse(res.success,
            "DOUBLE BOOKING - overlap detection is not working");
}

@test:Config {dependsOn: [testConfirmBookingSucceeds]}
function testSameDayTurnoverIsAllowed() returns error? {
    // 10-15 is confirmed. 15-20 starts on the checkout day, which is
    // standard hotel turnover and must be permitted.
    BookPropertyResponse booked = check cl->BookProperty({
        guestId: "GUEST-2",
        propertyId: testPropertyId,
        checkIn: "2026-09-15",
        checkOut: "2026-09-20"
    });
    test:assertTrue(booked.success, booked.message);

    ConfirmBookingResponse res = check cl->ConfirmBooking({
        guestId: "GUEST-2",
        cartItemId: booked.cartItemId
    });
    test:assertTrue(res.success,
            "turnover blocked - the overlap check is too strict");
}

@test:Config {}
function testConfirmRejectsUnknownCartItem() returns error? {
    ConfirmBookingResponse res = check cl->ConfirmBooking({
        guestId: "GUEST-1",
        cartItemId: "CART-99999"
    });
    test:assertFalse(res.success);
}


// =====================================================
// REMOVE - returns the region's remaining listings
// =====================================================

@test:Config {dependsOn: [testSameDayTurnoverIsAllowed]}
function testRemovePropertyReturnsRegionList() returns error? {
    // The brief requires the new full list of available properties
    // in that Host's region, not a bare confirmation.
    RemovePropertyResponse res = check cl->RemoveProperty({
        propertyId: testPropertyId,
        hostId: "HOST-1"
    });
    test:assertTrue(res.success, res.message);
    test:assertEquals(res.region, "KHOMAS");
    test:assertEquals(res.count, res.properties.length(),
            "count must match the array length");
}

@test:Config {}
function testRemoveRejectsWrongOwner() returns error? {
    AddPropertyResponse added = check cl->AddProperty({
        hostId: "HOST-1",
        name: "Ownership Test",
        location: "Somewhere",
        region: "Erongo",
        propertyType: LODGE,
        pricePerNight: 1200.0,
        status: AVAILABLE
    });

    RemovePropertyResponse res = check cl->RemoveProperty({
        propertyId: added.propertyId,
        hostId: "HOST-99"
    });
    test:assertFalse(res.success, "a host must not delete another's listing");
}
