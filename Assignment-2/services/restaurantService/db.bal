import ballerina/sql;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;

configurable boolean durableStateEnabled = false;
configurable string mysqlHost = "localhost";
configurable int mysqlPort = 3306;
configurable string mysqlDatabase = "restaurant";
configurable string mysqlUser = "restaurant_app";
configurable string mysqlPassword = "";

mysql:Client|sql:Error restaurantDb = error("restaurant database is not initialized");

type RestaurantRepository object {
    public function saveRestaurant(Restaurant restaurant) returns error?;
    public function getRestaurant(string id) returns Restaurant|error?;
    public function listRestaurants() returns Restaurant[]|error;
    public function saveHours(string restaurantId, string openFrom, string openTo) returns error?;
    public function saveMenuItem(MenuItem item) returns error?;
    public function getMenuItem(string id) returns MenuItem|error?;
    public function listMenuItems(string restaurantId) returns MenuItem[]|error;
    public function saveKitchenOrder(KitchenOrder kitchenOrder) returns error?;
    public function getKitchenOrder(string id) returns KitchenOrder|error?;
    public function listPendingKitchenOrders(string restaurantId) returns KitchenOrder[]|error;
};

type RestaurantRow record {|
    string id;
    string name;
    string address;
    boolean active;
    string openFrom;
    string openTo;
|};

type MenuItemRow record {|
    string id;
    string restaurantId;
    string name;
    decimal unitPrice;
    boolean available;
    int stockQty;
|};

type KitchenOrderRow record {|
    string id;
    string restaurantId;
    string itemsJson;
    string status;
    int paymentConfirmed;
|};

class InMemoryRestaurantRepository {
    *RestaurantRepository;

    public function saveRestaurant(Restaurant restaurant) returns error? {
        restaurants[restaurant.id] = restaurant;
    }

    public function getRestaurant(string id) returns Restaurant? {
        return restaurants[id];
    }

    public function listRestaurants() returns Restaurant[] {
        Restaurant[] result = [];
        foreach Restaurant restaurant in restaurants {
            if restaurant.active {
                result.push(restaurant);
            }
        }
        return result;
    }

    public function saveHours(string restaurantId, string openFrom, string openTo) returns error? {
        Restaurant? restaurant = restaurants[restaurantId];
        if restaurant is Restaurant {
            restaurant.openFrom = openFrom;
            restaurant.openTo = openTo;
            restaurants[restaurantId] = restaurant;
        }
    }

    public function saveMenuItem(MenuItem item) returns error? {
        menuItems[item.id] = item;
    }

    public function getMenuItem(string id) returns MenuItem? {
        return menuItems[id];
    }

    public function listMenuItems(string restaurantId) returns MenuItem[] {
        MenuItem[] result = [];
        foreach MenuItem item in menuItems {
            if item.restaurantId == restaurantId {
                result.push(item);
            }
        }
        return result;
    }

    public function saveKitchenOrder(KitchenOrder kitchenOrder) returns error? {
        kitchenOrders[kitchenOrder.id] = kitchenOrder;
    }

    public function getKitchenOrder(string id) returns KitchenOrder? {
        return kitchenOrders[id];
    }

    public function listPendingKitchenOrders(string restaurantId) returns KitchenOrder[] {
        KitchenOrder[] result = [];
        foreach KitchenOrder kitchenOrder in kitchenOrders {
            if kitchenOrder.restaurantId == restaurantId &&
                kitchenOrder.status == "PENDING_DECISION" {
                result.push(kitchenOrder);
            }
        }
        return result;
    }
}

class MySqlRestaurantRepository {
    *RestaurantRepository;

    public function saveRestaurant(Restaurant restaurant) returns error? {
        return saveRestaurantToMySql(restaurant);
    }

    public function getRestaurant(string id) returns Restaurant|error? {
        return getRestaurantFromMySql(id);
    }

    public function listRestaurants() returns Restaurant[]|error {
        return listRestaurantsFromMySql();
    }

    public function saveHours(string restaurantId, string openFrom, string openTo) returns error? {
        return saveRestaurantHoursToMySql(restaurantId, openFrom, openTo);
    }

    public function saveMenuItem(MenuItem item) returns error? {
        return saveMenuItemToMySql(item);
    }

    public function getMenuItem(string id) returns MenuItem|error? {
        return getMenuItemFromMySql(id);
    }

    public function listMenuItems(string restaurantId) returns MenuItem[]|error {
        return listMenuItemsFromMySql(restaurantId);
    }

    public function saveKitchenOrder(KitchenOrder kitchenOrder) returns error? {
        return saveKitchenOrderToMySql(kitchenOrder);
    }

    public function getKitchenOrder(string id) returns KitchenOrder|error? {
        return getKitchenOrderFromMySql(id);
    }

    public function listPendingKitchenOrders(string restaurantId) returns KitchenOrder[]|error {
        return listPendingKitchenOrdersFromMySql(restaurantId);
    }
}

RestaurantRepository restaurantRepository = new InMemoryRestaurantRepository();

function initRestaurantRepository() returns error? {
    if !durableStateEnabled {
        return;
    }
    restaurantDb = check new (
        host = mysqlHost,
        user = mysqlUser,
        password = mysqlPassword,
        database = mysqlDatabase,
        port = mysqlPort,
        connectionPool = {maxOpenConnections: 10}
    );
    restaurantRepository = new MySqlRestaurantRepository();
}

function saveRestaurantToMySql(Restaurant restaurant) returns error? {
    mysql:Client db = check restaurantDb;
    _ = check db->execute(
        `INSERT INTO restaurants (id, name, address, contact, is_active)
         VALUES (${restaurant.id}, ${restaurant.name}, ${restaurant.address}, '',
             ${restaurant.active})
         ON DUPLICATE KEY UPDATE name = VALUES(name), address = VALUES(address),
             is_active = VALUES(is_active)`
    );
}

function getRestaurantFromMySql(string id) returns Restaurant|error? {
    mysql:Client db = check restaurantDb;
    stream<RestaurantRow, sql:Error?> rows = db->query(
        `SELECT r.id, r.name, r.address, r.is_active AS active,
            COALESCE((SELECT TIME_FORMAT(h.opens_at, '%H:%i') FROM restaurant_hours h
                WHERE h.restaurant_id = r.id ORDER BY h.day_of_week LIMIT 1), '00:00') AS openFrom,
            COALESCE((SELECT TIME_FORMAT(h.closes_at, '%H:%i') FROM restaurant_hours h
                WHERE h.restaurant_id = r.id ORDER BY h.day_of_week LIMIT 1), '23:59') AS openTo
         FROM restaurants r WHERE r.id = ${id}`
    );
    record {| RestaurantRow value; |}|error? next = rows.next();
    if next is error || next is () {
        return next is error ? next : ();
    }
    RestaurantRow row = next.value;
    return {
        id: row.id, name: row.name, address: row.address, active: row.active,
        openFrom: row.openFrom, openTo: row.openTo
    };
}

function listRestaurantsFromMySql() returns Restaurant[]|error {
    mysql:Client db = check restaurantDb;
    stream<RestaurantRow, sql:Error?> rows = db->query(
        `SELECT r.id, r.name, r.address, r.is_active AS active,
            COALESCE((SELECT TIME_FORMAT(h.opens_at, '%H:%i') FROM restaurant_hours h
                WHERE h.restaurant_id = r.id ORDER BY h.day_of_week LIMIT 1), '00:00') AS openFrom,
            COALESCE((SELECT TIME_FORMAT(h.closes_at, '%H:%i') FROM restaurant_hours h
                WHERE h.restaurant_id = r.id ORDER BY h.day_of_week LIMIT 1), '23:59') AS openTo
         FROM restaurants r WHERE r.is_active = TRUE`
    );
    Restaurant[] result = [];
    while true {
        record {| RestaurantRow value; |}|error? next = rows.next();
        if next is error {
            return next;
        }
        if next is () {
            break;
        }
        RestaurantRow row = next.value;
        result.push({
            id: row.id, name: row.name, address: row.address, active: row.active,
            openFrom: row.openFrom, openTo: row.openTo
        });
    }
    return result;
}

function saveRestaurantHoursToMySql(string restaurantId, string openFrom, string openTo)
        returns error? {
    mysql:Client db = check restaurantDb;
    _ = check db->execute(
        `INSERT INTO restaurant_hours (restaurant_id, day_of_week, opens_at, closes_at)
         VALUES (${restaurantId}, 1, ${openFrom}, ${openTo})
         ON DUPLICATE KEY UPDATE opens_at = VALUES(opens_at), closes_at = VALUES(closes_at)`
    );
}

function saveMenuItemToMySql(MenuItem item) returns error? {
    mysql:Client db = check restaurantDb;
    _ = check db->execute(
        `INSERT INTO menu_items (id, restaurant_id, name, price, is_available, stock_qty)
         VALUES (${item.id}, ${item.restaurantId}, ${item.name}, ${item.unitPrice},
             ${item.available}, ${item.stockQty})
         ON DUPLICATE KEY UPDATE name = VALUES(name), price = VALUES(price),
             is_available = VALUES(is_available), stock_qty = VALUES(stock_qty)`
    );
}

function getMenuItemFromMySql(string id) returns MenuItem|error? {
    mysql:Client db = check restaurantDb;
    stream<MenuItemRow, sql:Error?> rows = db->query(
        `SELECT id, restaurant_id AS restaurantId, name, price AS unitPrice,
            is_available AS available, stock_qty AS stockQty
         FROM menu_items WHERE id = ${id}`
    );
    record {| MenuItemRow value; |}|error? next = rows.next();
    if next is error || next is () {
        return next is error ? next : ();
    }
    MenuItemRow row = next.value;
    return {
        id: row.id, restaurantId: row.restaurantId, name: row.name,
        unitPrice: row.unitPrice, available: row.available, stockQty: row.stockQty
    };
}

function listMenuItemsFromMySql(string restaurantId) returns MenuItem[]|error {
    mysql:Client db = check restaurantDb;
    stream<MenuItemRow, sql:Error?> rows = db->query(
        `SELECT id, restaurant_id AS restaurantId, name, price AS unitPrice,
            is_available AS available, stock_qty AS stockQty
         FROM menu_items WHERE restaurant_id = ${restaurantId}`
    );
    MenuItem[] result = [];
    while true {
        record {| MenuItemRow value; |}|error? next = rows.next();
        if next is error {
            return next;
        }
        if next is () {
            break;
        }
        MenuItemRow row = next.value;
        result.push({
            id: row.id, restaurantId: row.restaurantId, name: row.name,
            unitPrice: row.unitPrice, available: row.available, stockQty: row.stockQty
        });
    }
    return result;
}

function saveKitchenOrderToMySql(KitchenOrder kitchenOrder) returns error? {
    mysql:Client db = check restaurantDb;
    string itemsJson = (<json>kitchenOrder.items).toJsonString();
    string? rejectReason = kitchenOrder.status == "REJECTED" ? "RESTAURANT_REJECTED" : ();
    _ = check db->execute(
        `INSERT INTO kitchen_orders (order_id, restaurant_id, status, items_json, received_at,
            decided_at, payment_confirmed_at, reject_reason)
         VALUES (${kitchenOrder.id}, ${kitchenOrder.restaurantId}, ${kitchenOrder.status},
            CAST(${itemsJson} AS JSON), CURRENT_TIMESTAMP(6),
            IF(${kitchenOrder.status} = 'PENDING_DECISION', NULL, CURRENT_TIMESTAMP(6)),
            IF(${kitchenOrder.paymentConfirmed}, CURRENT_TIMESTAMP(6), NULL), ${rejectReason})
         ON DUPLICATE KEY UPDATE restaurant_id = VALUES(restaurant_id),
            status = VALUES(status), items_json = VALUES(items_json),
            decided_at = IF(VALUES(status) = 'PENDING_DECISION', decided_at,
                COALESCE(decided_at, CURRENT_TIMESTAMP(6))),
            payment_confirmed_at = IF(VALUES(payment_confirmed_at) IS NULL, NULL,
                COALESCE(payment_confirmed_at, CURRENT_TIMESTAMP(6))),
            reject_reason = VALUES(reject_reason)`
    );
}

function getKitchenOrderFromMySql(string id) returns KitchenOrder|error? {
    mysql:Client db = check restaurantDb;
    stream<KitchenOrderRow, sql:Error?> rows = db->query(
        `SELECT order_id AS id, restaurant_id AS restaurantId, CAST(items_json AS CHAR) AS itemsJson,
            status, payment_confirmed_at IS NOT NULL AS paymentConfirmed
         FROM kitchen_orders WHERE order_id = ${id}`
    );
    record {| KitchenOrderRow value; |}|error? next = rows.next();
    if next is error || next is () {
        return next is error ? next : ();
    }
    return kitchenOrderFromRow(next.value);
}

function listPendingKitchenOrdersFromMySql(string restaurantId) returns KitchenOrder[]|error {
    mysql:Client db = check restaurantDb;
    stream<KitchenOrderRow, sql:Error?> rows = db->query(
        `SELECT order_id AS id, restaurant_id AS restaurantId, CAST(items_json AS CHAR) AS itemsJson,
            status, payment_confirmed_at IS NOT NULL AS paymentConfirmed
         FROM kitchen_orders WHERE restaurant_id = ${restaurantId}
            AND status = 'PENDING_DECISION'`
    );
    KitchenOrder[] result = [];
    while true {
        record {| KitchenOrderRow value; |}|error? next = rows.next();
        if next is error {
            return next;
        }
        if next is () {
            break;
        }
        KitchenOrder|error kitchenOrder = kitchenOrderFromRow(next.value);
        if kitchenOrder is error {
            return kitchenOrder;
        }
        result.push(kitchenOrder);
    }
    return result;
}

function kitchenOrderFromRow(KitchenOrderRow row) returns KitchenOrder|error {
    json|error parsed = row.itemsJson.fromJsonString();
    if parsed is error {
        return parsed;
    }
    OrderLine[]|error items = <OrderLine[]>parsed;
    if items is error {
        return items;
    }
    return {
        id: row.id, restaurantId: row.restaurantId, items: items,
        status: row.status, paymentConfirmed: row.paymentConfirmed == 1
    };
}
