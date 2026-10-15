import ballerina/http;
import ballerina/uuid;

public type ErrorResponse record {|
    string 'error;
    string message;
|};

public type RestaurantInput record {|
    string name;
    string address;
|};

public type HoursInput record {|
    string openFrom;
    string openTo;
|};

public type Restaurant record {|
    string id;
    string name;
    string address;
    boolean active;
    string openFrom = "00:00";
    string openTo = "23:59";
|};

public type MenuItemInput record {|
    string name;
    decimal unitPrice;
    boolean available = true;
    int stockQty = 0;
|};

public type MenuItem record {|
    string id;
    string restaurantId;
    string name;
    decimal unitPrice;
    boolean available;
    int stockQty;
|};

public type OrderLine record {|
    string menuItemId;
    int quantity;
|};

public type KitchenOrder record {|
    string id;
    string restaurantId;
    OrderLine[] items;
    string status;
    boolean paymentConfirmed = false;
|};

map<RestaurantEvent> orderEvents = {};
map<Restaurant> restaurants = {};
map<MenuItem> menuItems = {};
map<KitchenOrder> kitchenOrders = {};

function failure(string code, string message, int status) returns http:Response {
    http:Response response = new;
    response.statusCode = status;
    response.setJsonPayload(<ErrorResponse>{'error: code, message: message});
    return response;
}

function validText(string value) returns boolean {
    return value.trim().length() > 0;
}

function inStock(KitchenOrder kitchenOrder) returns boolean {
    foreach OrderLine line in kitchenOrder.items {
        MenuItem? item = menuItems[line.menuItemId];
        if item is () || line.quantity <= 0 || !item.available || item.stockQty < line.quantity {
            return false;
        }
    }
    return true;
}

function checkKitchenOrderStock(KitchenOrder kitchenOrder) returns boolean|error {
    foreach OrderLine line in kitchenOrder.items {
        MenuItem|error? itemResult = restaurantRepository.getMenuItem(line.menuItemId);
        if itemResult is error {
            return itemResult;
        }
        MenuItem? item = itemResult;
        if item is () || line.quantity <= 0 || !item.available || item.stockQty < line.quantity {
            return false;
        }
    }
    return true;
}

function consumeStock(KitchenOrder kitchenOrder) returns error? {
    foreach OrderLine line in kitchenOrder.items {
        MenuItem|error? itemResult = restaurantRepository.getMenuItem(line.menuItemId);
        if itemResult is error {
            return itemResult;
        }
        MenuItem? item = itemResult;
        if item is MenuItem {
            item.stockQty -= line.quantity;
            check restaurantRepository.saveMenuItem(item);
        }
    }
}

service /restaurant on new http:Listener(9090) {
    function init() returns error? {
        check initRestaurantRepository();
        string demoRestaurantId = "00000000-0000-4000-8000-000000000002";
        Restaurant demoRestaurant = {
            id: demoRestaurantId, name: "Demo Restaurant",
            address: "Demo Restaurant, Windhoek", active: true
        };
        Restaurant|error? existingRestaurant = restaurantRepository.getRestaurant(demoRestaurantId);
        if existingRestaurant is error {
            return existingRestaurant;
        }
        if existingRestaurant is () {
            check restaurantRepository.saveRestaurant(demoRestaurant);
            check restaurantRepository.saveHours(demoRestaurantId, "00:00", "23:59");
        }
        MenuItem demoMenuItem = {
            id: "00000000-0000-4000-8000-000000000021",
            restaurantId: demoRestaurantId,
            name: "Demo item", unitPrice: 25.0, available: true, stockQty: 100
        };
        MenuItem|error? existingMenuItem = restaurantRepository.getMenuItem(demoMenuItem.id);
        if existingMenuItem is error {
            return existingMenuItem;
        }
        if existingMenuItem is () {
            check restaurantRepository.saveMenuItem(demoMenuItem);
        }
        return startRestaurantKafkaRuntime();
    }

    resource function get health() returns json {
        return {status: "UP", 'service: "restaurant"};
    }

    resource function post restaurants(@http:Payload RestaurantInput input)
            returns Restaurant|http:Response {
        if !validText(input.name) || !validText(input.address) {
            return failure("VALIDATION_ERROR", "name and address are required", 400);
        }
        string id = uuid:createType4AsString();
        Restaurant restaurant = {id, name: input.name.trim(), address: input.address.trim(), active: true};
        error? saved = restaurantRepository.saveRestaurant(restaurant);
        if saved is error { return failure("DATABASE_ERROR", "restaurant could not be saved", 503); }
        return restaurant;
    }

    resource function get restaurants() returns Restaurant[]|http:Response {
        Restaurant[]|error result = restaurantRepository.listRestaurants();
        if result is error { return failure("DATABASE_ERROR", "restaurants could not be loaded", 503); }
        return result;
    }

    resource function get restaurants/[string id]() returns Restaurant|http:Response {
        Restaurant|error? restaurantResult = restaurantRepository.getRestaurant(id);
        if restaurantResult is error { return failure("DATABASE_ERROR", "restaurant lookup failed", 503); }
        Restaurant? restaurant = restaurantResult;
        if restaurant is () {
            return failure("NOT_FOUND", "restaurant not found", 404);
        }
        return restaurant;
    }

    resource function put restaurants/[string id]/hours(@http:Payload HoursInput hours)
            returns Restaurant|http:Response {
        Restaurant|error? restaurantResult = restaurantRepository.getRestaurant(id);
        if restaurantResult is error { return failure("DATABASE_ERROR", "restaurant lookup failed", 503); }
        Restaurant? restaurant = restaurantResult;
        if restaurant is () {
            return failure("NOT_FOUND", "restaurant not found", 404);
        }
        if hours.openFrom.length() != 5 || hours.openTo.length() != 5 {
            return failure("VALIDATION_ERROR", "hours must use HH:MM", 400);
        }
        restaurant.openFrom = hours.openFrom;
        restaurant.openTo = hours.openTo;
        error? saved = restaurantRepository.saveHours(id, hours.openFrom, hours.openTo);
        if saved is error { return failure("DATABASE_ERROR", "restaurant hours could not be saved", 503); }
        return restaurant;
    }

    resource function post restaurants/[string id]/menu(@http:Payload MenuItemInput input)
            returns MenuItem|http:Response {
        Restaurant|error? restaurantResult = restaurantRepository.getRestaurant(id);
        if restaurantResult is error { return failure("DATABASE_ERROR", "restaurant lookup failed", 503); }
        if restaurantResult is () {
            return failure("NOT_FOUND", "restaurant not found", 404);
        }
        if !validText(input.name) || input.unitPrice < <decimal>0 || input.stockQty < 0 {
            return failure("VALIDATION_ERROR", "invalid menu item or stock", 400);
        }
        string itemId = uuid:createType4AsString();
        MenuItem item = {id: itemId, restaurantId: id, name: input.name.trim(),
            unitPrice: input.unitPrice, available: input.available, stockQty: input.stockQty};
        error? saved = restaurantRepository.saveMenuItem(item);
        if saved is error { return failure("DATABASE_ERROR", "menu item could not be saved", 503); }
        return item;
    }

    resource function get restaurants/[string id]/menu() returns MenuItem[]|http:Response {
        Restaurant|error? restaurantResult = restaurantRepository.getRestaurant(id);
        if restaurantResult is error { return failure("DATABASE_ERROR", "restaurant lookup failed", 503); }
        if restaurantResult is () {
            return failure("NOT_FOUND", "restaurant not found", 404);
        }
        MenuItem[]|error result = restaurantRepository.listMenuItems(id);
        if result is error { return failure("DATABASE_ERROR", "menu could not be loaded", 503); }
        return result;
    }

    resource function put menu/[string itemId](@http:Payload MenuItemInput input)
            returns MenuItem|http:Response {
        MenuItem|error? itemResult = restaurantRepository.getMenuItem(itemId);
        if itemResult is error { return failure("DATABASE_ERROR", "menu item lookup failed", 503); }
        MenuItem? item = itemResult;
        if item is () {
            return failure("NOT_FOUND", "menu item not found", 404);
        }
        if input.unitPrice < <decimal>0 || input.stockQty < 0 || !validText(input.name) {
            return failure("VALIDATION_ERROR", "invalid menu item or stock", 400);
        }
        item.name = input.name.trim();
        item.unitPrice = input.unitPrice;
        item.available = input.available;
        item.stockQty = input.stockQty;
        error? saved = restaurantRepository.saveMenuItem(item);
        if saved is error { return failure("DATABASE_ERROR", "menu item could not be saved", 503); }
        return item;
    }

    resource function post restaurants/[string id]/orders(@http:Payload OrderLine[] items)
            returns KitchenOrder|http:Response {
        Restaurant|error? restaurantResult = restaurantRepository.getRestaurant(id);
        if restaurantResult is error { return failure("DATABASE_ERROR", "restaurant lookup failed", 503); }
        if restaurantResult is () || items.length() == 0 {
            return failure("VALIDATION_ERROR", "restaurant and order items are required", 400);
        }
        string orderId = uuid:createType4AsString();
        KitchenOrder kitchenOrder = {id: orderId, restaurantId: id, items, status: "PENDING_DECISION"};
        error? saved = restaurantRepository.saveKitchenOrder(kitchenOrder);
        if saved is error { return failure("DATABASE_ERROR", "kitchen order could not be saved", 503); }
        return kitchenOrder;
    }

    resource function get restaurants/[string id]/orders() returns KitchenOrder[]|http:Response {
        Restaurant|error? restaurantResult = restaurantRepository.getRestaurant(id);
        if restaurantResult is error { return failure("DATABASE_ERROR", "restaurant lookup failed", 503); }
        if restaurantResult is () {
            return failure("NOT_FOUND", "restaurant not found", 404);
        }
        KitchenOrder[]|error result = restaurantRepository.listPendingKitchenOrders(id);
        if result is error { return failure("DATABASE_ERROR", "kitchen orders could not be loaded", 503); }
        return result;
    }

    resource function post orders/[string orderId]/accept() returns KitchenOrder|http:Response {
        KitchenOrder|error? orderResult = restaurantRepository.getKitchenOrder(orderId);
        if orderResult is error { return failure("DATABASE_ERROR", "kitchen order lookup failed", 503); }
        KitchenOrder? kitchenOrder = orderResult;
        if kitchenOrder is () {
            return failure("NOT_FOUND", "kitchen order not found", 404);
        }
        if kitchenOrder.status != "PENDING_DECISION" {
            return failure("INVALID_STATE", "order is not pending decision", 409);
        }
        boolean|error stockResult = checkKitchenOrderStock(kitchenOrder);
        if stockResult is error { return failure("DATABASE_ERROR", "menu stock lookup failed", 503); }
        if !stockResult {
            kitchenOrder.status = "REJECTED";
            error? saved = restaurantRepository.saveKitchenOrder(kitchenOrder);
            if saved is error { return failure("DATABASE_ERROR", "kitchen order could not be saved", 503); }
            return failure("OUT_OF_STOCK", "one or more menu items are unavailable", 409);
        }
        error? consumed = consumeStock(kitchenOrder);
        if consumed is error { return failure("DATABASE_ERROR", "menu stock could not be saved", 503); }
        kitchenOrder.status = "ACCEPTED";
        error? saved = restaurantRepository.saveKitchenOrder(kitchenOrder);
        if saved is error { return failure("DATABASE_ERROR", "kitchen order could not be saved", 503); }
        error? published = publishManualRestaurantEvent(orderId, "restaurant.accepted", kitchenOrder);
        if published is error { return failure("PUBLISH_FAILED", "restaurant.accepted could not be published", 503); }
        return kitchenOrder;
    }

    resource function post orders/[string orderId]/reject() returns KitchenOrder|http:Response {
        KitchenOrder|error? orderResult = restaurantRepository.getKitchenOrder(orderId);
        if orderResult is error { return failure("DATABASE_ERROR", "kitchen order lookup failed", 503); }
        KitchenOrder? kitchenOrder = orderResult;
        if kitchenOrder is () {
            return failure("NOT_FOUND", "kitchen order not found", 404);
        }
        if kitchenOrder.status != "PENDING_DECISION" {
            return failure("INVALID_STATE", "order is not pending decision", 409);
        }
        kitchenOrder.status = "REJECTED";
        error? saved = restaurantRepository.saveKitchenOrder(kitchenOrder);
        if saved is error { return failure("DATABASE_ERROR", "kitchen order could not be saved", 503); }
        error? published = publishManualRestaurantEvent(orderId, "restaurant.rejected",
            {reason: "RESTAURANT_REJECTED", orderId: orderId});
        if published is error { return failure("PUBLISH_FAILED", "restaurant.rejected could not be published", 503); }
        return kitchenOrder;
    }

    resource function post orders/[string orderId]/preparing() returns KitchenOrder|http:Response {
        KitchenOrder|error? orderResult = restaurantRepository.getKitchenOrder(orderId);
        if orderResult is error { return failure("DATABASE_ERROR", "kitchen order lookup failed", 503); }
        KitchenOrder? kitchenOrder = orderResult;
        if kitchenOrder is () {
            return failure("NOT_FOUND", "kitchen order not found", 404);
        }
        if kitchenOrder.status != "ACCEPTED" || !kitchenOrder.paymentConfirmed {
            return failure("INVALID_STATE", "payment must be confirmed before preparing", 409);
        }
        kitchenOrder.status = "PREPARING";
        error? saved = restaurantRepository.saveKitchenOrder(kitchenOrder);
        if saved is error { return failure("DATABASE_ERROR", "kitchen order could not be saved", 503); }
        error? published = publishManualRestaurantEvent(orderId, "restaurant.preparing", kitchenOrder);
        if published is error { return failure("PUBLISH_FAILED", "restaurant.preparing could not be published", 503); }
        return kitchenOrder;
    }

    resource function post orders/[string orderId]/ready() returns KitchenOrder|http:Response {
        KitchenOrder|error? orderResult = restaurantRepository.getKitchenOrder(orderId);
        if orderResult is error { return failure("DATABASE_ERROR", "kitchen order lookup failed", 503); }
        KitchenOrder? kitchenOrder = orderResult;
        if kitchenOrder is () {
            return failure("NOT_FOUND", "kitchen order not found", 404);
        }
        if kitchenOrder.status != "PREPARING" {
            return failure("INVALID_STATE", "order is not preparing", 409);
        }
        kitchenOrder.status = "READY";
        error? saved = restaurantRepository.saveKitchenOrder(kitchenOrder);
        if saved is error { return failure("DATABASE_ERROR", "kitchen order could not be saved", 503); }
        error? published = publishManualRestaurantEvent(orderId, "restaurant.ready", kitchenOrder);
        if published is error { return failure("PUBLISH_FAILED", "restaurant.ready could not be published", 503); }
        return kitchenOrder;
    }

    resource function post orders/[string orderId]/confirm() returns KitchenOrder|http:Response {
        KitchenOrder|error? orderResult = restaurantRepository.getKitchenOrder(orderId);
        if orderResult is error { return failure("DATABASE_ERROR", "kitchen order lookup failed", 503); }
        KitchenOrder? kitchenOrder = orderResult;
        if kitchenOrder is () {
            return failure("NOT_FOUND", "kitchen order not found", 404);
        }
        if kitchenOrder.status != "ACCEPTED" {
            return failure("INVALID_STATE", "order is not accepted", 409);
        }
        kitchenOrder.paymentConfirmed = true;
        error? saved = restaurantRepository.saveKitchenOrder(kitchenOrder);
        if saved is error { return failure("DATABASE_ERROR", "kitchen order could not be saved", 503); }
        return kitchenOrder;
    }

    resource function get internal/restaurants/[string id]/validate() returns json|http:Response {
        Restaurant|error? restaurantResult = restaurantRepository.getRestaurant(id);
        if restaurantResult is error { return failure("DATABASE_ERROR", "restaurant lookup failed", 503); }
        Restaurant? restaurant = restaurantResult;
        if restaurant is () {
            return failure("NOT_FOUND", "restaurant not found", 404);
        }
        json[] items = [];
        MenuItem[]|error menuResult = restaurantRepository.listMenuItems(id);
        if menuResult is error { return failure("DATABASE_ERROR", "menu could not be loaded", 503); }
        foreach MenuItem item in menuResult {
            items.push({menuItemId: item.id, name: item.name, unitPrice: item.unitPrice,
                available: item.available, stockQty: item.stockQty});
        }
        return {active: restaurant.active, openNow: true, pickupAddress: restaurant.address, items};
    }
}
