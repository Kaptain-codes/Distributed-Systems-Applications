isolated table<Restaurant> key(restaurantId) restaurantTable = table [];

isolated function memoryListRestaurants() returns Restaurant[] {
    lock {
        return restaurantTable.toArray().clone();
    }
}

isolated function memoryFindRestaurant(string restaurantId) returns Restaurant? {
    lock {
        Restaurant? restaurant = restaurantTable[restaurantId];
        return restaurant is Restaurant ? restaurant.clone() : ();
    }
}

// Registers a restaurant with an initially valid menu and schedule.
isolated function memoryCreateRestaurant(Restaurant restaurant) returns Restaurant|error {
    lock {
        Restaurant storedRestaurant = restaurant.clone();
        if restaurantTable.hasKey(storedRestaurant.restaurantId) {
            return error(string `Restaurant '${storedRestaurant.restaurantId}' already exists`);
        }
        restaurantTable.add(storedRestaurant);
        return storedRestaurant.clone();
    }
}

// Adds a menu item whose identifier is unique within the restaurant.
isolated function memoryAddMenuItem(string restaurantId, MenuItem menuItem)
        returns MenuItem|error {
    lock {
        Restaurant? restaurant = restaurantTable[restaurantId];
        if restaurant is () {
            return error(string `Restaurant '${restaurantId}' was not found`);
        }
        if menuItem.price < 0d || menuItem.availableQuantity < 0 {
            return error("Menu item price and inventory cannot be negative");
        }
        MenuItem storedItem = menuItem.clone();
        foreach MenuItem existingItem in restaurant.menu {
            if existingItem.menuItemId == storedItem.menuItemId {
                return error(string `Menu item '${storedItem.menuItemId}' already exists`);
            }
        }
        restaurant.menu.push(storedItem);
        return storedItem.clone();
    }
}

// Sets the current inventory and derives whether the item can be ordered.
isolated function memoryUpdateInventory(string restaurantId, string menuItemId,
        int availableQuantity) returns MenuItem|error {
    lock {
        Restaurant? restaurant = restaurantTable[restaurantId];
        if restaurant is () {
            return error(string `Restaurant '${restaurantId}' was not found`);
        }
        if availableQuantity < 0 {
            return error("Available quantity cannot be negative");
        }
        foreach MenuItem menuItem in restaurant.menu {
            if menuItem.menuItemId == menuItemId {
                menuItem.availableQuantity = availableQuantity;
                menuItem.available = availableQuantity > 0;
                return menuItem.clone();
            }
        }
        return error(string `Menu item '${menuItemId}' was not found`);
    }
}

public isolated function clearRestaurants() {
    lock {
        restaurantTable = table [];
    }
}

