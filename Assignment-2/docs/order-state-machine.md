# Order state machine

```mermaid
stateDiagram-v2
    [*] --> CREATED
    CREATED --> CONFIRMED: restaurantAcceptedAt && paymentStatus == PAID
    CREATED --> CANCELLED: payment failed/rejected/timeout/customer cancel
    CONFIRMED --> PREPARING: restaurantAcceptedAt && paymentStatus == PAID
    CONFIRMED --> CANCELLED: timeout/customer cancel
    PREPARING --> READY: restaurantAcceptedAt && paymentStatus == PAID
    PREPARING --> CANCELLED: timeout
    READY --> OUT_FOR_DELIVERY: deliveryAssignedAt && picked up
    READY --> CANCELLED: no driver/delivery failed
    OUT_FOR_DELIVERY --> DELIVERED: delivery completed
    OUT_FOR_DELIVERY --> CANCELLED: delivery failed
```

Guard fields include `restaurantAcceptedAt`, `paymentRequestedAt`,
`deliveryAssignedAt`, `paymentStatus`, and the persisted status/version.
Conditional transitions reject stale or invalid events.
