import ballerina/http;

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

map<Restaurant> restaurants = {};
map<MenuItem> menuItems = {};
map<KitchenOrder> kitchenOrders = {};
map<RestaurantEvent> orderEvents = {};
int nextRestaurantId = 1;
int nextMenuId = 1;

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

function consumeStock(KitchenOrder kitchenOrder) {
    foreach OrderLine line in kitchenOrder.items {
        MenuItem? item = menuItems[line.menuItemId];
        if item is MenuItem {
            item.stockQty -= line.quantity;
            menuItems[item.id] = item;
        }
    }
}

service /restaurant on new http:Listener(9090) {
    function init() returns error? {
        restaurants["00000000-0000-4000-8000-000000000002"] = {
            id: "00000000-0000-4000-8000-000000000002",
            name: "Demo Restaurant", address: "Demo Restaurant, Windhoek", active: true
        };
        menuItems["00000000-0000-4000-8000-000000000021"] = {
            id: "00000000-0000-4000-8000-000000000021",
            restaurantId: "00000000-0000-4000-8000-000000000002",
            name: "Demo item", unitPrice: 25.0, available: true, stockQty: 100
        };
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
        string id = "res-" + nextRestaurantId.toString();
        nextRestaurantId += 1;
        Restaurant restaurant = {id, name: input.name.trim(), address: input.address.trim(), active: true};
        restaurants[id] = restaurant;
        return restaurant;
    }

    resource function get restaurants() returns Restaurant[] {
        Restaurant[] result = [];
        foreach string restaurantKey in restaurants.keys() {
            Restaurant? restaurant = restaurants[restaurantKey];
            if restaurant is Restaurant && restaurant.active {
                result.push(restaurant);
            }
        }
        return result;
    }

    resource function get restaurants/[string id]() returns Restaurant|http:Response {
        Restaurant? restaurant = restaurants[id];
        if restaurant is () {
            return failure("NOT_FOUND", "restaurant not found", 404);
        }
        return restaurant;
    }

    resource function put restaurants/[string id]/hours(@http:Payload HoursInput hours)
            returns Restaurant|http:Response {
        Restaurant? restaurant = restaurants[id];
        if restaurant is () {
            return failure("NOT_FOUND", "restaurant not found", 404);
        }
        if hours.openFrom.length() != 5 || hours.openTo.length() != 5 {
            return failure("VALIDATION_ERROR", "hours must use HH:MM", 400);
        }
        restaurant.openFrom = hours.openFrom;
        restaurant.openTo = hours.openTo;
        restaurants[id] = restaurant;
        return restaurant;
    }

    resource function post restaurants/[string id]/menu(@http:Payload MenuItemInput input)
            returns MenuItem|http:Response {
        if !restaurants.hasKey(id) {
            return failure("NOT_FOUND", "restaurant not found", 404);
        }
        if !validText(input.name) || input.unitPrice < <decimal>0 || input.stockQty < 0 {
            return failure("VALIDATION_ERROR", "invalid menu item or stock", 400);
        }
        string itemId = "item-" + nextMenuId.toString();
        nextMenuId += 1;
        MenuItem item = {id: itemId, restaurantId: id, name: input.name.trim(),
            unitPrice: input.unitPrice, available: input.available, stockQty: input.stockQty};
        menuItems[itemId] = item;
        return item;
    }

    resource function get restaurants/[string id]/menu() returns MenuItem[]|http:Response {
        if !restaurants.hasKey(id) {
            return failure("NOT_FOUND", "restaurant not found", 404);
        }
        MenuItem[] result = [];
        foreach string itemKey in menuItems.keys() {
            MenuItem? item = menuItems[itemKey];
            if item is MenuItem && item.restaurantId == id {
                result.push(item);
            }
        }
        return result;
    }

    resource function put menu/[string itemId](@http:Payload MenuItemInput input)
            returns MenuItem|http:Response {
        MenuItem? item = menuItems[itemId];
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
        menuItems[itemId] = item;
        return item;
    }

    resource function post restaurants/[string id]/orders(@http:Payload OrderLine[] items)
            returns KitchenOrder|http:Response {
        if !restaurants.hasKey(id) || items.length() == 0 {
            return failure("VALIDATION_ERROR", "restaurant and order items are required", 400);
        }
        string orderId = "order-" + kitchenOrders.length().toString();
        KitchenOrder kitchenOrder = {id: orderId, restaurantId: id, items, status: "PENDING_DECISION"};
        kitchenOrders[orderId] = kitchenOrder;
        return kitchenOrder;
    }

    resource function get restaurants/[string id]/orders() returns KitchenOrder[]|http:Response {
        if !restaurants.hasKey(id) {
            return failure("NOT_FOUND", "restaurant not found", 404);
        }
        KitchenOrder[] result = [];
        foreach string orderKey in kitchenOrders.keys() {
            KitchenOrder? kitchenOrder = kitchenOrders[orderKey];
            if kitchenOrder is KitchenOrder && kitchenOrder.restaurantId == id &&
                    kitchenOrder.status == "PENDING_DECISION" {
                result.push(kitchenOrder);
            }
        }
        return result;
    }

    resource function post orders/[string orderId]/accept() returns KitchenOrder|http:Response {
        KitchenOrder? kitchenOrder = kitchenOrders[orderId];
        if kitchenOrder is () {
            return failure("NOT_FOUND", "kitchen order not found", 404);
        }
        if kitchenOrder.status != "PENDING_DECISION" {
            return failure("INVALID_STATE", "order is not pending decision", 409);
        }
        if !inStock(kitchenOrder) {
            kitchenOrder.status = "REJECTED";
            kitchenOrders[orderId] = kitchenOrder;
            return failure("OUT_OF_STOCK", "one or more menu items are unavailable", 409);
        }
        consumeStock(kitchenOrder);
        kitchenOrder.status = "ACCEPTED";
        kitchenOrders[orderId] = kitchenOrder;
        error? published = publishManualRestaurantEvent(orderId, "restaurant.accepted", kitchenOrder);
        if published is error { return failure("PUBLISH_FAILED", "restaurant.accepted could not be published", 503); }
        return kitchenOrder;
    }

    resource function post orders/[string orderId]/reject() returns KitchenOrder|http:Response {
        KitchenOrder? kitchenOrder = kitchenOrders[orderId];
        if kitchenOrder is () {
            return failure("NOT_FOUND", "kitchen order not found", 404);
        }
        if kitchenOrder.status != "PENDING_DECISION" {
            return failure("INVALID_STATE", "order is not pending decision", 409);
        }
        kitchenOrder.status = "REJECTED";
        kitchenOrders[orderId] = kitchenOrder;
        error? published = publishManualRestaurantEvent(orderId, "restaurant.rejected",
            {reason: "RESTAURANT_REJECTED", orderId: orderId});
        if published is error { return failure("PUBLISH_FAILED", "restaurant.rejected could not be published", 503); }
        return kitchenOrder;
    }

    resource function post orders/[string orderId]/preparing() returns KitchenOrder|http:Response {
        KitchenOrder? kitchenOrder = kitchenOrders[orderId];
        if kitchenOrder is () {
            return failure("NOT_FOUND", "kitchen order not found", 404);
        }
        if kitchenOrder.status != "ACCEPTED" || !kitchenOrder.paymentConfirmed {
            return failure("INVALID_STATE", "payment must be confirmed before preparing", 409);
        }
        kitchenOrder.status = "PREPARING";
        kitchenOrders[orderId] = kitchenOrder;
        error? published = publishManualRestaurantEvent(orderId, "restaurant.preparing", kitchenOrder);
        if published is error { return failure("PUBLISH_FAILED", "restaurant.preparing could not be published", 503); }
        return kitchenOrder;
    }

    resource function post orders/[string orderId]/ready() returns KitchenOrder|http:Response {
        KitchenOrder? kitchenOrder = kitchenOrders[orderId];
        if kitchenOrder is () {
            return failure("NOT_FOUND", "kitchen order not found", 404);
        }
        if kitchenOrder.status != "PREPARING" {
            return failure("INVALID_STATE", "order is not preparing", 409);
        }
        kitchenOrder.status = "READY";
        kitchenOrders[orderId] = kitchenOrder;
        error? published = publishManualRestaurantEvent(orderId, "restaurant.ready", kitchenOrder);
        if published is error { return failure("PUBLISH_FAILED", "restaurant.ready could not be published", 503); }
        return kitchenOrder;
    }

    resource function post orders/[string orderId]/confirm() returns KitchenOrder|http:Response {
        KitchenOrder? kitchenOrder = kitchenOrders[orderId];
        if kitchenOrder is () {
            return failure("NOT_FOUND", "kitchen order not found", 404);
        }
        if kitchenOrder.status != "ACCEPTED" {
            return failure("INVALID_STATE", "order is not accepted", 409);
        }
        kitchenOrder.paymentConfirmed = true;
        kitchenOrders[orderId] = kitchenOrder;
        return kitchenOrder;
    }

    resource function get internal/restaurants/[string id]/validate() returns json|http:Response {
        Restaurant? restaurant = restaurants[id];
        if restaurant is () {
            return failure("NOT_FOUND", "restaurant not found", 404);
        }
        json[] items = [];
        foreach string itemKey in menuItems.keys() {
            MenuItem? item = menuItems[itemKey];
            if item is MenuItem && item.restaurantId == id {
                items.push({menuItemId: item.id, name: item.name, unitPrice: item.unitPrice,
                    available: item.available, stockQty: item.stockQty});
            }
        }
        return {active: restaurant.active, openNow: true, pickupAddress: restaurant.address, items};
    }
}
