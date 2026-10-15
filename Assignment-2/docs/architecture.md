# Assignment 2 architecture

```mermaid
flowchart LR
    Client[HTTP client] --> Gateway[Gateway :8080]
    Gateway --> Order[Order service]
    Gateway --> Restaurant[Restaurant service]
    Gateway --> Payment[Payment service]
    Gateway --> Delivery[Delivery service]
    Gateway --> Customer[Customer service]
    Gateway --> Notification[Notification service]
    Gateway --> Admin[Admin service]
    Order <--> Kafka[(Kafka)]
    Restaurant <--> Kafka
    Payment <--> Kafka
    Delivery <--> Kafka
    Admin <--> Kafka
    Order --> OrderDB[(MongoDB order-db)]
    Admin --> AdminDB[(MongoDB admin-db)]
    Restaurant -. process-local demo state .-> RestaurantDB[(restaurant-db)]
    Payment -. process-local demo state .-> PaymentDB[(payment-db)]
    Delivery -. process-local demo state .-> DeliveryDB[(delivery-db)]
    Customer -. process-local demo state .-> CustomerDB[(customer-db)]
    Notification -. process-local demo state .-> NotificationDB[(notification-db)]
    Kafka --> Zookeeper[ZooKeeper]
```

All application containers listen on port 9090 internally. The gateway is the
supported client entry point. Only order and admin state is durable in the
current development runtime; the remaining service state is process-local.
