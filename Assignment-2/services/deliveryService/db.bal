import ballerinax/mssql;
import ballerinax/mssql.driver as _;
import ballerina/sql;

configurable boolean durableStateEnabled = false;
configurable string sqlServerHost = "localhost";
configurable int sqlServerPort = 1433;
configurable string sqlServerDatabase = "delivery";
configurable string sqlServerUser = "sa";
configurable string sqlServerPassword = "";

mssql:Client|sql:Error deliveryDb = error("delivery database is not initialized");

type DriverRow record {|
    string driverId;
    string name;
    string status;
    string? lastAssignedAt;
|};

type DeliveryRow record {|
    string deliveryId;
    string orderId;
    string pickupAddress;
    string deliveryAddress;
    string status;
    string? driverId;
    string? failureReason;
    string createdAt;
    string updatedAt;
|};

function initDeliveryDb() returns error? {
    if !durableStateEnabled {
        return;
    }
    deliveryDb = check new (
        host = sqlServerHost,
        user = sqlServerUser,
        password = sqlServerPassword,
        database = sqlServerDatabase,
        port = sqlServerPort,
        connectionPool = {maxOpenConnections: 10}
    );
}

function dbDriver(string driverId) returns Driver|error? {
    if !durableStateEnabled {
        return drivers[driverId];
    }
    mssql:Client db = check deliveryDb;
    stream<DriverRow, sql:Error?> rows = db->query(
        `SELECT CONVERT(varchar(36), id) AS driverId, name, status,
                CONVERT(varchar(33), last_assigned_at, 126) AS lastAssignedAt
         FROM drivers WHERE id = ${driverId}`
    );
    record {| DriverRow value; |}|error? next = rows.next();
    if next is error || next is () {
        return next is error ? next : ();
    }
    DriverRow row = next.value;
    return {driverId: row.driverId, name: row.name, status: row.status};
}

function dbCreateDriver(Driver driver) returns error? {
    if !durableStateEnabled {
        drivers[driver.driverId] = driver;
        return;
    }
    mssql:Client db = check deliveryDb;
    _ = check db->execute(
        `INSERT INTO drivers (id, name, phone, status)
         VALUES (${driver.driverId}, ${driver.name}, '', ${driver.status})`
    );
}

function dbSetDriverStatus(string driverId, string status) returns error? {
    if !durableStateEnabled {
        Driver? driver = drivers[driverId];
        if driver is Driver {
            driver.status = status;
            drivers[driverId] = driver;
        }
        return;
    }
    mssql:Client db = check deliveryDb;
    _ = check db->execute(`UPDATE drivers SET status = ${status} WHERE id = ${driverId}`);
}

function dbAvailableDriver() returns Driver|error? {
    if !durableStateEnabled {
        foreach string id in drivers.keys() {
            Driver? driver = drivers[id];
            if driver is Driver && driver.status == "AVAILABLE" {
                return driver;
            }
        }
        return ();
    }
    mssql:Client db = check deliveryDb;
    stream<DriverRow, sql:Error?> rows = db->query(
        `UPDATE TOP (1) drivers WITH (UPDLOCK, READPAST, ROWLOCK)
         SET status = 'BUSY', last_assigned_at = SYSUTCDATETIME()
         OUTPUT CONVERT(varchar(36), inserted.id) AS driverId, inserted.name,
                inserted.status,
                CONVERT(varchar(33), inserted.last_assigned_at, 126) AS lastAssignedAt
         WHERE status = 'AVAILABLE'`
    );
    record {| DriverRow value; |}|error? next = rows.next();
    if next is error || next is () {
        return next is error ? next : ();
    }
    DriverRow row = next.value;
    return {driverId: row.driverId, name: row.name, status: "BUSY"};
}

function dbFindDelivery(string orderId) returns Delivery|error? {
    if !durableStateEnabled {
        return findDeliveryByOrderId(orderId);
    }
    mssql:Client db = check deliveryDb;
    stream<DeliveryRow, sql:Error?> rows = db->query(
        `SELECT CONVERT(varchar(36), id) AS deliveryId,
                CONVERT(varchar(36), order_id) AS orderId, pickup_address AS pickupAddress,
                dropoff_address AS deliveryAddress, status,
                CONVERT(varchar(36), driver_id) AS driverId, failure_reason AS failureReason,
                CONVERT(varchar(33), assigned_at, 126) AS createdAt,
                CONVERT(varchar(33), COALESCE(completed_at, assigned_at), 126) AS updatedAt
         FROM deliveries WHERE order_id = ${orderId}`
    );
    record {| DeliveryRow value; |}|error? next = rows.next();
    if next is error || next is () {
        return next is error ? next : ();
    }
    DeliveryRow row = next.value;
    return {
        deliveryId: row.deliveryId, orderId: row.orderId, pickupAddress: row.pickupAddress,
        deliveryAddress: row.deliveryAddress, status: row.status, driverId: row.driverId,
        failureReason: row.failureReason, createdAt: row.createdAt, updatedAt: row.updatedAt
    };
}

function dbSaveDelivery(Delivery delivery) returns error? {
    if !durableStateEnabled {
        deliveries[delivery.deliveryId] = delivery;
        return;
    }
    mssql:Client db = check deliveryDb;
    _ = check db->execute(
        `MERGE deliveries AS target
         USING (SELECT ${delivery.deliveryId} AS id, ${delivery.orderId} AS order_id) AS source
         ON target.order_id = source.order_id
         WHEN MATCHED THEN UPDATE SET status = ${delivery.status},
             failure_reason = ${delivery.failureReason}, completed_at = CASE
             WHEN ${delivery.status} = 'COMPLETED' THEN SYSUTCDATETIME() ELSE completed_at END
         WHEN NOT MATCHED THEN INSERT (id, order_id, restaurant_id, driver_id, pickup_address,
             dropoff_address, status, assigned_at)
         VALUES (${delivery.deliveryId}, ${delivery.orderId}, '00000000-0000-0000-0000-000000000000',
             ${delivery.driverId}, ${delivery.pickupAddress}, ${delivery.deliveryAddress},
             ${delivery.status}, SYSUTCDATETIME());`
    );
}

function dbCreateDeliveryIfAbsent(Delivery delivery) returns boolean|error {
    if !durableStateEnabled {
        foreach Delivery existing in deliveries {
            if existing.orderId == delivery.orderId {
                return false;
            }
        }
        deliveries[delivery.deliveryId] = delivery;
        return true;
    }
    mssql:Client db = check deliveryDb;
    sql:ExecutionResult result = check db->execute(
        `INSERT INTO deliveries (id, order_id, restaurant_id, driver_id, pickup_address,
             dropoff_address, status, assigned_at)
         SELECT ${delivery.deliveryId}, ${delivery.orderId},
             '00000000-0000-0000-0000-000000000000', ${delivery.driverId},
             ${delivery.pickupAddress}, ${delivery.deliveryAddress}, ${delivery.status},
             SYSUTCDATETIME()
         WHERE NOT EXISTS (
             SELECT 1 FROM deliveries WITH (UPDLOCK, HOLDLOCK)
             WHERE order_id = ${delivery.orderId}
         )`
    );
    return result.affectedRowCount > 0;
}

function dbMarkEvent(string eventId) returns error? {
    if !durableStateEnabled {
        deliveryProcessedEvents[eventId] = true;
        return;
    }
    mssql:Client db = check deliveryDb;
    _ = check db->execute(
        `INSERT INTO processed_events (event_id, processed_at)
         SELECT ${eventId}, SYSUTCDATETIME()
         WHERE NOT EXISTS (SELECT 1 FROM processed_events WHERE event_id = ${eventId})`
    );
}

function dbEventProcessed(string eventId) returns boolean|error {
    if !durableStateEnabled {
        return deliveryProcessedEvents[eventId] == true;
    }
    mssql:Client db = check deliveryDb;
    stream<record {| int total; |}, sql:Error?> rows = db->query(
        `SELECT COUNT(*) AS total FROM processed_events WHERE event_id = ${eventId}`
    );
    record {| record {| int total; |} value; |}|error? next = rows.next();
    if next is error || next is () {
        return next is error ? next : false;
    }
    record {| int total; |} row = next.value;
    return row is record {| int total; |} && row.total > 0;
}
