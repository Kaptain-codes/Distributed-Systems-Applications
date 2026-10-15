import ballerinax/mongodb;

public isolated function listRestaurants() returns Restaurant[]|error {
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("restaurants");
        stream<Restaurant, error?> restaurantStream =
            check collection->find({}, targetType = Restaurant);
        return from Restaurant restaurant in restaurantStream
            select restaurant;
    }
    return memoryListRestaurants();
}

public isolated function findRestaurant(string restaurantId) returns Restaurant?|error {
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("restaurants");
        return collection->findOne({restaurantId}, targetType = Restaurant);
    }
    return memoryFindRestaurant(restaurantId);
}

public isolated function createRestaurant(Restaurant restaurant) returns Restaurant|error {
    check validateInitialMenu(restaurant.menu);
    if databaseBackend == MONGODB {
        Restaurant? existing = check findRestaurant(restaurant.restaurantId);
        if existing is Restaurant {
            return error(string `Restaurant '${restaurant.restaurantId}' already exists`);
        }
        mongodb:Collection collection = check configuredMongoCollection("restaurants");
        check collection->insertOne(restaurant);
        return restaurant;
    }
    return memoryCreateRestaurant(restaurant);
}

public isolated function addMenuItem(string restaurantId, MenuItem menuItem)
        returns MenuItem|error {
    if menuItem.price < 0d || menuItem.availableQuantity < 0 {
        return error("Menu item price and inventory cannot be negative");
    }
    Restaurant? restaurant = check findRestaurant(restaurantId);
    if restaurant is () {
        return error(string `Restaurant '${restaurantId}' was not found`);
    }
    foreach MenuItem existingItem in restaurant.menu {
        if existingItem.menuItemId == menuItem.menuItemId {
            return error(string `Menu item '${menuItem.menuItemId}' already exists`);
        }
    }
    if databaseBackend == MONGODB {
        restaurant.menu.push(menuItem.clone());
        mongodb:Collection collection = check configuredMongoCollection("restaurants");
        _ = check collection->updateOne({restaurantId}, {set: {menu: restaurant.menu}});
    } else {
        return memoryAddMenuItem(restaurantId, menuItem);
    }
    return menuItem;
}

public isolated function updateInventory(string restaurantId, string menuItemId,
        int availableQuantity) returns MenuItem|error {
    if availableQuantity < 0 {
        return error("Available quantity cannot be negative");
    }
    if databaseBackend == MONGODB {
        mongodb:Collection collection = check configuredMongoCollection("restaurants");
        mongodb:UpdateResult result = check collection->updateOne(
            {restaurantId, "menu.menuItemId": menuItemId},
            {
            set: {
                "menu.$.availableQuantity": availableQuantity,
                "menu.$.available": availableQuantity > 0
            }
        }
        );
        if result.matchedCount == 0 {
            return restaurantOrMenuNotFound(restaurantId, menuItemId);
        }
    } else {
        return memoryUpdateInventory(restaurantId, menuItemId, availableQuantity);
    }
    Restaurant? restaurant = check findRestaurant(restaurantId);
    if restaurant is Restaurant {
        foreach MenuItem menuItem in restaurant.menu {
            if menuItem.menuItemId == menuItemId {
                return menuItem;
            }
        }
    }
    return error(string `Menu item '${menuItemId}' was not found`);
}

isolated function validateInitialMenu(MenuItem[] menu) returns error? {
    map<boolean> identifiers = {};
    foreach MenuItem menuItem in menu {
        if menuItem.price < 0d || menuItem.availableQuantity < 0 {
            return error(string `Menu item '${menuItem.menuItemId}' has invalid price or inventory`);
        }
        if identifiers.hasKey(menuItem.menuItemId) {
            return error(string `Menu item '${menuItem.menuItemId}' is duplicated`);
        }
        identifiers[menuItem.menuItemId] = true;
    }
}

isolated function restaurantOrMenuNotFound(string restaurantId, string menuItemId)
        returns MenuItem|error {
    Restaurant? restaurant = check findRestaurant(restaurantId);
    return restaurant is () ? error(string `Restaurant '${restaurantId}' was not found`) :
        error(string `Menu item '${menuItemId}' was not found`);
}
