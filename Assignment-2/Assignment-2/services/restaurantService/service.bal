import ballerina/http;

configurable int servicePort = 9102;

isolated function restaurantNotFound(string message) returns NotFoundResponse => {body: {message}};

isolated function restaurantConflict(string message) returns ConflictResponse => {body: {message}};

isolated function invalidRestaurantRequest(string message) returns BadRequestResponse => {body: {message}};

// Manages restaurant profiles, menus, opening hours, and inventory.
service /restaurants on new http:Listener(servicePort) {
    // Provides a lightweight readiness signal for container orchestration.
    isolated resource function get health() returns map<string> =>
        {status: "UP", component: "restaurant_service"};

    isolated resource function get .() returns Restaurant[]|error => listRestaurants();

    isolated resource function post .(Restaurant restaurant) returns Restaurant|ConflictResponse {
        Restaurant|error result = createRestaurant(restaurant);
        return result is error ? restaurantConflict(result.message()) : result;
    }

    isolated resource function get [string restaurantId]() returns Restaurant|NotFoundResponse|error {
        Restaurant? restaurant = check findRestaurant(restaurantId);
        return restaurant is Restaurant ? restaurant :
            restaurantNotFound(string `Restaurant '${restaurantId}' was not found`);
    }

    isolated resource function post [string restaurantId]/menu(MenuItem menuItem)
            returns MenuItem|NotFoundResponse|ConflictResponse|BadRequestResponse {
        MenuItem|error result = addMenuItem(restaurantId, menuItem);
        if result is MenuItem {
            return result;
        }
        if result.message().includes("not found") {
            return restaurantNotFound(result.message());
        }
        return result.message().includes("already exists") ? restaurantConflict(result.message()) :
            invalidRestaurantRequest(result.message());
    }

    isolated resource function put [string restaurantId]/menu/[string menuItemId]/inventory(
            InventoryUpdate update) returns MenuItem|NotFoundResponse|BadRequestResponse {
        MenuItem|error result = updateInventory(restaurantId, menuItemId, update.availableQuantity);
        if result is MenuItem {
            return result;
        }
        return result.message().includes("negative") ? invalidRestaurantRequest(result.message()) :
            restaurantNotFound(result.message());
    }
}

