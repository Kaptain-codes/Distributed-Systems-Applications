import ballerina/test;

@test:BeforeEach
function resetRestaurantRepository() {
    clearRestaurants();
}

@test:Config
function testInventoryControlsAvailability() returns error? {
    _ = check createRestaurant({
                                   restaurantId: "RES-001",
                                   name: "Windhoek Kitchen",
                                   address: "Independence Avenue"
                               });
    _ = check addMenuItem("RES-001", {
                                         menuItemId: "ITEM-001",
                                         name: "Kapana Plate",
                                         description: "Beef and salsa",
                                         price: 75.00,
                                         availableQuantity: 5
                                     });
    MenuItem menuItem = check updateInventory("RES-001", "ITEM-001", 0);
    test:assertFalse(menuItem.available);
}
