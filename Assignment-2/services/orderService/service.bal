import ballerina/http;
import ballerina/time;
import ballerina/uuid;

service /'order on new http:Listener(9090) {

    resource function get health() returns json {
        return {status: "UP", 'service: "order"};
    }

    resource function post .(http:Caller caller, http:Request req) returns error? {
        json body = check req.getJsonPayload();
        CreateOrderRequest payload = check body.cloneWithType();
        http:Response res = new;

        boolean ok = check customerExists(payload.customerId);
        if !ok {
            res.statusCode = 400;
            res.setJsonPayload({message: string `customer ${payload.customerId} not found`});
            check caller->respond(res);
            return;
        }

        decimal total = 0;
        foreach OrderItem item in payload.items {
            total += <decimal>item.quantity * item.price;
        }

        string id = uuid:createType1AsString();
        string now = time:utcToString(time:utcNow());
        Order newOrder = {
            id,
            customerId: payload.customerId,
            restaurantId: payload.restaurantId,
            items: payload.items,
            total,
            status: "CREATED",
            createdAt: now,
            updatedAt: now
        };

        _ = check orderCollection->insertOne(newOrder);
        check publishStatusEvent(newOrder);

        res.statusCode = 201;
        res.setJsonPayload(newOrder.toJson());
        check caller->respond(res);
    }

    resource function get [string id](http:Caller caller) returns error? {
        map<json> filter = {"id": {"$eq": id}};
        Order? result = check orderCollection->findOne(filter);
        http:Response res = new;

        if result is () {
            res.statusCode = 404;
            res.setJsonPayload({message: string `order ${id} not found`});
        } else {
            res.statusCode = 200;
            res.setJsonPayload(result.toJson());
        }
        check caller->respond(res);
    }

    resource function put [string id]/status(http:Caller caller, http:Request req) returns error? {
        json body = check req.getJsonPayload();
        UpdateOrderStatusRequest payload = check body.cloneWithType();
        http:Response res = new;

        map<json> filter = {"id": {"$eq": id}};

        Order? existing = check orderCollection->findOne(filter);
        if existing is () {
            res.statusCode = 404;
            res.setJsonPayload({message: string `order ${id} not found`});
            check caller->respond(res);
            return;
        }

        Order ord = existing;
        OrderStatus current = ord.status;

        if !isValidTransition(current, payload.status) {
            res.statusCode = 409;
            res.setJsonPayload({
                message: string `invalid transition ${current} -> ${payload.status}`
            });
            check caller->respond(res);
            return;
        }

        string now = time:utcToString(time:utcNow());
        Order updated = {
            id: ord.id,
            customerId: ord.customerId,
            restaurantId: ord.restaurantId,
            items: ord.items,
            total: ord.total,
            status: payload.status,
            createdAt: ord.createdAt,
            updatedAt: now
        };

        _ = check orderCollection->deleteOne(filter);
        _ = check orderCollection->insertOne(updated);
        check publishStatusEvent(updated);

        res.statusCode = 200;
        res.setJsonPayload(updated.toJson());
        check caller->respond(res);
    }
}